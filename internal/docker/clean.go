package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Mode は掃除の強さ。
type Mode int

const (
	// Light は停止コンテナ / dangling image / 匿名 volume / 未使用 build cache。
	Light Mode = iota
	// Heavy は上記 + 未使用 image 全部 + 共有ぶんも含む build cache 全部。
	Heavy
)

func (m Mode) label() string {
	if m == Heavy {
		return "重"
	}
	return "軽"
}

// IO は出力先。
type IO struct {
	Stdout io.Writer
	Stderr io.Writer
	// Confirm は実行前の承認を取る。nil なら TTY から読む。
	Confirm func(prompt string) bool
}

func (w IO) out() io.Writer {
	if w.Stdout == nil {
		return io.Discard
	}
	return w.Stdout
}

func (w IO) err() io.Writer {
	if w.Stderr == nil {
		return io.Discard
	}
	return w.Stderr
}

// row はプレビューの1行を整形する。
//
// **ラベルは表示幅で詰める**（fish の `string pad`）。`fmt` の %-18s は
// ルーン数で詰めるので日本語ラベルの桁が崩れる。
func row(label string, count string, size string, note string) string {
	out := fmt.Sprintf("  %s%s 件   %s", PadRight(label, 18), PadLeft(count, 4), size)
	if note != "" {
		out += "   " + note
	}
	return out
}

// Builders は buildx のビルダー名を列挙する。
//
// **`docker builder prune` は --builder を付けないとカレントビルダーしか
// 掃除しない。** docker-container ドライバのビルダーと daemon 側の default
// ビルダーは別のキャッシュを持つ（実測で 11.2GB と 6.8GB）ため、両方を
// 対象にしないと片方が永久に残る。
//
// 列挙できなければ空を返す（呼び出し側は --builder を付けずカレントだけを扱う）。
func Builders(ctx context.Context, r execx.Runner) []string {
	res, err := r.Run(ctx, execx.Cmd{Name: "docker", Args: []string{"buildx", "ls", "--format", "json"}})
	if err != nil || !res.OK() {
		return nil
	}
	var out []string
	for _, line := range strings.Split(strings.TrimSuffix(res.Stdout, "\n"), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var v struct{ Name string }
		if json.Unmarshal([]byte(line), &v) == nil && v.Name != "" {
			out = append(out, v.Name)
		}
	}
	return out
}

// buildCacheSizes は回収可能な build cache のサイズを全ビルダーぶん集める。
//
// **`--filter until=` は渡さない。** 実測で docker ドライバ・docker-container
// ドライバのどちらでも無視され、7日以上前のレコードが残っていても一切
// 回収されなかった。
func buildCacheSizes(ctx context.Context, r execx.Runner) []string {
	var sizes []string
	collect := func(args ...string) {
		res, err := r.Run(ctx, execx.Cmd{Name: "docker", Args: args})
		if err != nil || !res.OK() {
			return
		}
		for _, line := range strings.Split(strings.TrimSuffix(res.Stdout, "\n"), "\n") {
			if strings.TrimSpace(line) == "" {
				continue
			}
			var v struct {
				Reclaimable bool   `json:"Reclaimable"`
				Size        string `json:"Size"`
			}
			if json.Unmarshal([]byte(line), &v) == nil && v.Reclaimable {
				sizes = append(sizes, v.Size)
			}
		}
	}

	builders := Builders(ctx, r)
	if len(builders) == 0 {
		collect("buildx", "du", "--format", "json")
		return sizes
	}
	for _, b := range builders {
		collect("buildx", "du", "--builder", b, "--format", "json")
	}
	return sizes
}

func countLines(s string) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	return len(strings.Fields(s))
}

var hexVolume = regexp.MustCompile(`^[0-9a-f]{64}$`)

// Preview はプレビューを表示する。
func Preview(ctx context.Context, r execx.Runner, cfg Config, s *Stats, mode Mode, w IO, dirExists func(string) bool) {
	out := w.out()
	fmt.Fprintf(out, "docker 掃除プレビュー（%s）\n", mode.label())

	var known int64

	// 停止コンテナ
	stoppedN := 0
	if res, err := r.Run(ctx, execx.Cmd{Name: "docker",
		Args: []string{"ps", "-a", "-q", "-f", "status=exited", "-f", "status=created"}}); err == nil && res.OK() {
		stoppedN = countLines(res.Stdout)
	}
	stoppedB := SizeToBytesOrZero(s.DFField("Containers", "Reclaimable"))
	fmt.Fprintln(out, row("停止コンテナ", strconv.Itoa(stoppedN), FormatBytes(stoppedB), ""))
	known += stoppedB

	// image
	if mode == Heavy {
		total, _ := strconv.Atoi(s.DFField("Images", "TotalCount"))
		active, _ := strconv.Atoi(s.DFField("Images", "Active"))
		imgB := SizeToBytesOrZero(s.DFField("Images", "Reclaimable"))
		fmt.Fprintln(out, row("未使用 image", strconv.Itoa(total-active), FormatBytes(imgB), ""))
		known += imgB
	} else {
		imgN := 0
		if res, err := r.Run(ctx, execx.Cmd{Name: "docker",
			Args: []string{"images", "-f", "dangling=true", "-q"}}); err == nil && res.OK() {
			imgN = countLines(res.Stdout)
		}
		fmt.Fprintln(out, row("dangling image", strconv.Itoa(imgN), "-", "※共有レイヤのため事前見積り不可"))
	}

	// volume（匿名のみ。64桁 hex 名で判定する）
	volN := 0
	if res, err := r.Run(ctx, execx.Cmd{Name: "docker",
		Args: []string{"volume", "ls", "-q", "-f", "dangling=true"}}); err == nil && res.OK() {
		for _, v := range strings.Fields(res.Stdout) {
			if hexVolume.MatchString(v) {
				volN++
			}
		}
	}
	volB := SizeToBytesOrZero(s.DFField("Local Volumes", "Reclaimable"))
	fmt.Fprintln(out, row("未使用 volume", strconv.Itoa(volN), FormatBytes(volB), "※ named volume は対象外"))
	known += volB

	// build cache
	//
	// **サイズは軽モードでは出さない。** buildx du の Size は共有レイヤを含む
	// うえ、軽モードはそのうち「使われていないぶん」だけを消すため、合算すると
	// 実際の回収量と桁が変わる（246件/5.4GB と表示して実際の回収が 0B になった）。
	sizes := buildCacheSizes(ctx, r)
	if mode == Heavy {
		bcB := SizeToBytesOrZero(sizes...)
		fmt.Fprintln(out, row("build cache", strconv.Itoa(len(sizes)),
			"最大"+FormatBytes(bcB), "※全ビルダー合算"))
		known += bcB
	} else {
		fmt.Fprintln(out, row("build cache", strconv.Itoa(len(sizes)),
			"-", "※全ビルダー合算 / うち未使用ぶんのみ削除"))
	}

	fmt.Fprintln(out, "  ──────────────────────────────")
	fmt.Fprintf(out, "  回収見込み 最大 約 %s\n", FormatBytes(known))
	if mode == Heavy {
		fmt.Fprintln(out, "  （buildx du のサイズは共有レイヤを含むため実際はこれより少ない）")
	} else {
		fmt.Fprintln(out, "  （image と build cache の回収量は事前に確定できないため未計上。")
		fmt.Fprintln(out, "    実際の回収量は実行後の「回収:」行を見る）")
	}
	fmt.Fprintln(out, "")

	previewRunning(ctx, cfg, s, w, dirExists)
}

// classified は種別を付けた稼働コンテナ。
type classified struct {
	Kind Kind
	Container
}

// previewRunning は稼働中コンテナの一覧とコピペ用コマンドを出す。
func previewRunning(ctx context.Context, cfg Config, s *Stats, w IO, dirExists func(string) bool) {
	out := w.out()
	fmt.Fprintln(out, "稼働中コンテナ（停止は手動判断）")

	long := LongRunning(s, cfg, false)
	rows := make([]classified, 0, len(long))
	for _, c := range long {
		rows = append(rows, classified{ContainerKind(c.ComposeProject, c.ComposeDir, dirExists), c})
	}

	if len(rows) == 0 {
		fmt.Fprintln(out, "  （閾値を超えて稼働しているコンテナはありません）")
	} else {
		for _, r := range rows {
			// **タグのパディングは括弧の外側に入れる**（`[main  ]` ではなく `[main]  `）。
			// wt / wtd の一覧と同じ規約
			tag := PadRight("["+string(r.Kind)+"]", 13)
			note := ""
			if r.AutoRemove {
				note = "   ※--rm: 停止で削除されます"
			}
			fmt.Fprintf(out, "  %s%-36s Up %s%s\n", tag, r.Name, HumanizeUptime(r.UptimeSeconds), note)
			// orphan だけ理由を添える。どの worktree の残骸か分かるのが実用上の価値
			if r.Kind == Orphan {
				fmt.Fprintf(out, "               └ working_dir なし: %s\n", r.ComposeDir)
			}
		}
	}

	// **除外で非表示になっている閾値超えを示す。** 出さないと docker ps と
	// 件数が合わず「表示に不足がある」ように見える
	if n := len(LongRunning(s, cfg, true)); n > 0 {
		fmt.Fprintf(out, "  （除外 %d 件 — docker_clean_ignore_patterns で非表示）\n", n)
	}

	if len(rows) == 0 {
		fmt.Fprintln(out, "")
		return
	}

	// 止めると判断したらコピペで済むよう、種別ごとにコマンドを出す。実行はしない。
	//
	// **種別で分けるのは停止の可逆性がまるで違うため。**
	//   compose    レシピが docker-compose.yml に残るので up で戻せる
	//   orphan     working_dir ごと消えているので戻せない（が確実な停止候補）
	//   standalone レシピが docker 側に残らない。--rm なら停止＝即削除
	var orphanProjects, composeProjects, standaloneNames []string
	standaloneRM := false
	for _, r := range rows {
		switch r.Kind {
		case Orphan:
			orphanProjects = appendUnique(orphanProjects, r.ComposeProject)
		case Compose:
			composeProjects = appendUnique(composeProjects, r.ComposeProject)
		default:
			standaloneNames = append(standaloneNames, r.Name)
			if r.AutoRemove {
				standaloneRM = true
			}
		}
	}

	fmt.Fprintln(out, "")
	fmt.Fprintln(out, "  停止する場合（コピペ用）:")
	if len(orphanProjects) > 0 {
		fmt.Fprintln(out, "  # orphan（working_dir が消えているため up では戻せません）")
		for _, p := range orphanProjects {
			fmt.Fprintf(out, "  docker compose -p %s down\n", p)
		}
	}
	if len(composeProjects) > 0 {
		fmt.Fprintln(out, "  # compose（up で戻せます）")
		for _, p := range composeProjects {
			fmt.Fprintf(out, "  docker compose -p %s down\n", p)
		}
	}
	if len(standaloneNames) > 0 {
		if standaloneRM {
			fmt.Fprintln(out, "  # standalone（※--rm のコンテナは停止で削除されます）")
		} else {
			fmt.Fprintln(out, "  # standalone")
		}
		fmt.Fprintf(out, "  docker container stop %s\n", strings.Join(standaloneNames, " "))
	}
	// **--refresh は最終行に独立して出す。** 起動時通知はキャッシュしか読まない
	// ため、停止しただけでは TTL が切れるまで古い件数を通知し続ける
	fmt.Fprintln(out, "  dclean --refresh")
	fmt.Fprintln(out, "")
	_ = ctx
}

func appendUnique(xs []string, s string) []string {
	for _, x := range xs {
		if x == s {
			return xs
		}
	}
	return append(xs, s)
}

var totalRe = regexp.MustCompile(`^(?:Total reclaimed space:|Total:)\s*(.+)$`)

// PruneCommands はモードに応じた prune の引数列を返す。
//
// **volume prune には軽・重どちらでも -a を付けない。** -a なしなら匿名 volume
// だけが対象になり、named volume（DB データ）が守られる。
//
// build cache は全ビルダーぶん実行する。軽と重の区別は -a の有無だけで付ける
// （`--filter until=` は実測で無視されるので使わない）。
func PruneCommands(mode Mode, builders []string) [][]string {
	cmds := [][]string{{"container", "prune", "-f"}}
	if mode == Heavy {
		cmds = append(cmds, []string{"image", "prune", "-a", "-f"})
	} else {
		cmds = append(cmds, []string{"image", "prune", "-f"})
	}
	cmds = append(cmds, []string{"volume", "prune", "-f"})

	base := []string{"builder", "prune", "-f"}
	if mode == Heavy {
		base = []string{"builder", "prune", "-a", "-f"}
	}
	if len(builders) == 0 {
		cmds = append(cmds, base)
		return cmds
	}
	for _, b := range builders {
		cmds = append(cmds, append(append([]string{}, base...), "--builder", b))
	}
	return cmds
}

// Run はモードに応じた prune を順に実行する。
// **1つのコマンドが失敗しても残りは続行し、最後に失敗件数を報告する。**
func Run(ctx context.Context, r execx.Runner, mode Mode, w IO) int {
	out := w.out()
	cmds := PruneCommands(mode, Builders(ctx, r))

	failed := 0
	var reclaimed int64

	for _, args := range cmds {
		joined := strings.Join(args, " ")
		fmt.Fprintf(out, "→ docker %s\n", joined)

		res, err := r.Run(ctx, execx.Cmd{Name: "docker", Args: args})
		body := res.Stdout + res.Stderr
		if err != nil || !res.OK() {
			fmt.Fprintf(out, "  失敗: docker %s\n", joined)
			for _, line := range splitNonEmpty(body) {
				fmt.Fprintf(w.err(), "  %s\n", line)
			}
			failed++
			continue
		}

		for _, line := range splitNonEmpty(body) {
			fmt.Fprintf(out, "  %s\n", line)
			// docker prune は "Total reclaimed space: 2.5GB"、
			// buildkit の prune は "Total:\t6.776GB" を出す。どちらも拾う
			if m := totalRe.FindStringSubmatch(strings.TrimSpace(line)); m != nil {
				reclaimed += SizeToBytesOrZero(strings.TrimSpace(m[1]))
			}
		}
	}

	fmt.Fprintln(out, "")
	fmt.Fprintf(out, "回収: %s\n", FormatBytes(reclaimed))

	if failed > 0 {
		fmt.Fprintf(w.err(), "%d 件のコマンドが失敗しました\n", failed)
		return 1
	}
	return 0
}

func splitNonEmpty(s string) []string {
	var out []string
	for _, line := range strings.Split(strings.TrimSuffix(s, "\n"), "\n") {
		if strings.TrimSpace(line) != "" {
			out = append(out, line)
		}
	}
	return out
}
