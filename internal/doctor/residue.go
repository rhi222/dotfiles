// Package doctor は環境とリポジトリの状態を点検する。
//
// **どちらも「情報提供」寄りの検査。** env-residue は見つかっても exit 0 に
// する（daily-update.sh から run_step_soft で呼ばれるので、非0を返すと毎日
// FAILED 通知が飛び、やがて無視されるようになる）。
package doctor

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// ResidueConfig は残骸チェックの設定。
type ResidueConfig struct {
	Home string
	// Repo は判定に使うリポジトリのルート。
	Repo string
	// FisherFilesFile はテスト用。fisher の一覧をファイルから読む。
	FisherFilesFile string
	// LiveSkillDirs は skill が実体化される場所（~/.claude/skills など）。
	LiveSkillDirs []string
}

// IO は出力先。
type IO struct {
	Stdout io.Writer
	Stderr io.Writer
}

func (w IO) out() io.Writer {
	if w.Stdout == nil {
		return io.Discard
	}
	return w.Stdout
}

// Residue は残骸1件。
type Residue struct {
	// Message は何が残っているか。
	Message string
	// Hint は撤去や復旧の手順（無ければ空）。
	Hint string
}

// CheckResidue は宣言のどこにも属さないのに環境に居座っているものを洗い出す。
//
// **既存のどのチェックにも掛からない種類の drift を埋めるためのもの。**
// migration-check は「リポジトリの作業状態」専用で環境は見ない。
func CheckResidue(ctx context.Context, r execx.Runner, cfg ResidueConfig) ([]Residue, []string) {
	var found []Residue
	var notes []string

	found = append(found, checkOldFzf(cfg)...)
	found = append(found, checkUntrackedFishFunctions(ctx, r, cfg)...)

	skills, note := checkUndeclaredSkills(cfg)
	found = append(found, skills...)
	if note != "" {
		notes = append(notes, note)
	}
	return found, notes
}

// checkOldFzf は install スクリプト時代の fzf の置き土産を見る。
//
// **mise が fzf を管理している今は二重で、PATH の並び次第で古い版を掴む
// 端末が出る。**
func checkOldFzf(cfg ResidueConfig) []Residue {
	var out []Residue
	if st, err := os.Stat(filepath.Join(cfg.Home, ".fzf")); err == nil && st.IsDir() {
		out = append(out, Residue{
			"~/.fzf/ が残っています（fzf は mise 管理なので二重）",
			"撤去: rm -rf ~/.fzf（bash 側で ~/.fzf.bash を source していないか先に確認）",
		})
	}
	if _, err := os.Lstat(filepath.Join(cfg.Home, ".fzf.bash")); err == nil {
		out = append(out, Residue{
			"~/.fzf.bash が残っています",
			"撤去: rm -f ~/.fzf.bash（.bashrc から source していないか先に確認）",
		})
	}
	return out
}

// fisherFiles は fisher が管理しているファイルの一覧を返す。
//
// **判定は名前の規約ではなく fisher 自身が持つ一覧で行う。** fisher は
// プラグインごとに universal 変数 `_fisher_<plugin>_files` へインストールした
// ファイルを記録している。「`_` 始まりはプラグイン」で切った初版は tide の
// `fish_prompt` / `fish_mode_prompt` / `tide`、`fisher` 本体、fzf.fish の
// `fzf_configure_bindings` を**誤検知した（実環境で5件）**。公開関数は
// 普通の名前を持つ。
//
// 第2戻り値は「一覧が引けたか」。引けなければ呼び出し側は `_` 始まりの
// 除外に落とす。
func fisherFiles(ctx context.Context, r execx.Runner, cfg ResidueConfig) ([]string, bool) {
	if cfg.FisherFilesFile != "" {
		b, err := os.ReadFile(cfg.FisherFilesFile)
		if err != nil {
			return nil, false
		}
		return splitLines(string(b)), true
	}

	res, err := r.Run(ctx, execx.Cmd{Name: "fish", Args: []string{"-c",
		`for v in (set -n | string match "_fisher_*_files")
             for f in $$v
               string replace -- "~" $HOME $f
             end
           end`}})
	if err != nil || !res.OK() {
		return nil, false
	}
	lines := splitLines(res.Stdout)
	return lines, len(lines) > 0
}

func splitLines(s string) []string {
	var out []string
	sc := bufio.NewScanner(strings.NewReader(s))
	for sc.Scan() {
		if line := strings.TrimSpace(sc.Text()); line != "" {
			out = append(out, line)
		}
	}
	return out
}

// checkUntrackedFishFunctions は追跡外の fish 関数を見る。
//
// ~/.config/fish/functions は fisher の置き場でもあるので、中身を全部残骸とは
// 言えない。除外は2つ——repo の my/functions が同名を持つもの（影にできていて
// 実害が無い）と、fisher が入れたもの。
func checkUntrackedFishFunctions(ctx context.Context, r execx.Runner, cfg ResidueConfig) []Residue {
	liveDir := filepath.Join(cfg.Home, ".config", "fish", "functions")
	repoDir := filepath.Join(cfg.Repo, ".config", "fish", "my", "functions")

	if st, err := os.Stat(liveDir); err != nil || !st.IsDir() {
		return nil
	}

	files, fisherKnown := fisherFiles(ctx, r, cfg)
	managed := map[string]bool{}
	for _, f := range files {
		managed[filepath.Base(f)] = true
	}

	entries, err := os.ReadDir(liveDir)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".fish") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	var out []Residue
	for _, base := range names {
		if _, err := os.Lstat(filepath.Join(repoDir, base)); err == nil {
			continue // repo 側が同名を持つ（影にできている）
		}
		if fisherKnown {
			if managed[base] {
				continue
			}
		} else if strings.HasPrefix(base, "_") {
			// 一覧が引けなかったので名前の規約に落ちる
			continue
		}
		out = append(out, Residue{
			fmt.Sprintf("追跡外の fish 関数: ~/.config/fish/functions/%s", base),
			"repo の .config/fish/my/functions/ にも fisher の管理下にもありません",
		})
	}
	return out
}

// checkUndeclaredSkills は宣言に無い skill を見る。
//
// 宣言は3系統——trusted（claude-skills.txt / gh が入れた実ディレクトリが正）、
// vendored（agents/skills-vendor/ → symlink が正）、自作（共用またはagent固有の
// skills/ → symlink が正）。
//
// **宣言が読めないときは skill の判定を丸ごと諦める。** 読めないまま
// 「宣言に無い」と言うと、正しく入っているものまで残骸に見えてしまう。
// 第2戻り値はその理由（諦めなかったときは空）。
func checkUndeclaredSkills(cfg ResidueConfig) ([]Residue, string) {
	declPath := filepath.Join(cfg.Repo, "scripts", "setup", "claude-skills.txt")
	b, err := os.ReadFile(declPath)
	if err != nil {
		return nil, fmt.Sprintf("  skill の宣言が読めないため skill の判定はしません: %s", declPath)
	}

	declared := map[string]bool{}
	for _, line := range splitLines(string(b)) {
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := fields[1]
		if i := strings.Index(name, "@"); i >= 0 {
			name = name[:i]
		}
		declared[name] = true
	}

	// 自作と vendored のディレクトリ名も宣言として扱う
	vendored := map[string]bool{}
	for _, d := range []string{
		filepath.Join(cfg.Repo, ".config", "agents", "skills"),
		filepath.Join(cfg.Repo, ".config", "claude", "skills"),
		filepath.Join(cfg.Repo, ".config", "codex", "skills"),
		filepath.Join(cfg.Repo, ".config", "agents", "skills-vendor"),
	} {
		for _, name := range subdirs(d) {
			declared[name] = true
		}
	}
	for _, name := range subdirs(filepath.Join(cfg.Repo, ".config", "agents", "skills-vendor")) {
		vendored[name] = true
	}

	var out []Residue
	for _, live := range cfg.LiveSkillDirs {
		for _, name := range subdirs(live) {
			// codex 同梱の .system 以下は宣言の対象外
			if strings.HasPrefix(name, ".") {
				continue
			}
			short := strings.TrimPrefix(live, cfg.Home+"/")

			// **vendored は symlink で入るのが正。** 実ディレクトリなら
			// 古い実体が居座っていて、Claude は古い版を読み続ける
			if vendored[name] {
				fi, lerr := os.Lstat(filepath.Join(live, name))
				if lerr == nil && fi.Mode()&os.ModeSymlink == 0 {
					out = append(out, Residue{
						fmt.Sprintf("vendored なのに実ディレクトリ: ~/%s/%s", short, name),
						"古い gh 版が読まれています。退避してから ./dotfilesLink.sh",
					})
				}
				continue
			}
			if declared[name] {
				continue
			}
			out = append(out, Residue{
				fmt.Sprintf("宣言に無い skill: ~/%s/%s", short, name),
				"trusted なら scripts/setup/claude-skills.txt に、そうでなければ skill-vendor.sh add へ",
			})
		}
	}
	return out, ""
}

// subdirs はディレクトリ直下のサブディレクトリ名を辞書順で返す。
func subdirs(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out
}

// RenderResidue は結果を Shell 版と同じ体裁で書く。
//
// **見つかっても exit 0。** 残骸があること自体は壊れている状態ではなく、
// 放置すると事故になりうる状態。毎日 FAILED が飛ぶと無視されるようになる。
func RenderResidue(w io.Writer, found []Residue, notes []string) int {
	for _, n := range notes {
		fmt.Fprintln(w, n)
	}
	for _, f := range found {
		fmt.Fprintf(w, "  %s\n", f.Message)
		if f.Hint != "" {
			fmt.Fprintf(w, "      %s\n", f.Hint)
		}
	}
	if len(found) == 0 {
		fmt.Fprintln(w, "残骸は見つかりませんでした")
	}
	// 機械可読サマリ。表示の体裁を変えても呼び出し側が壊れないようにする
	fmt.Fprintf(w, "env-residue: FOUND=%d\n", len(found))
	return 0
}
