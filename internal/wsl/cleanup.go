// Package wsl は WSL2 開発環境のキャッシュ掃除を行う。
//
// **開発環境の本体は触らない。** .cargo / .rustup / ~/go / mise / nvim /
// claude は対象外で、掃除するのは再取得できるキャッシュだけ。
package wsl

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Config は掃除1回分の設定。
type Config struct {
	Home string
	// Execute が偽なら何も削除しない（既定）。
	Execute bool
	// Color は stdout が TTY のとき真。
	Color bool
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

func (w IO) err() io.Writer {
	if w.Stderr == nil {
		return io.Discard
	}
	return w.Stderr
}

type palette struct{ bold, green, yellow, cyan, reset string }

func newPalette(color bool) palette {
	if !color {
		return palette{}
	}
	return palette{"\x1b[1m", "\x1b[32m", "\x1b[33m", "\x1b[36m", "\x1b[0m"}
}

// pathTarget はディレクトリを消すだけの対象。
type pathTarget struct {
	label string
	rel   string // Home からの相対
}

// cmdTarget はコマンド経由で掃除する対象。
type cmdTarget struct {
	label string
	bin   string
	// cacheHint は dry-run で見せるサイズの測定先（Home 相対。空なら測らない）。
	cacheHint string
	args      []string
}

// **パッケージマネージャのキャッシュはコマンドに任せる。** 自前で消すと
// 内部のインデックスと食い違う。
var cmdTargets = []cmdTarget{
	{"npm cache", "npm", ".npm", []string{"npm", "cache", "clean", "--force"}},
	{"uv cache", "uv", ".cache/uv", []string{"uv", "cache", "clean"}},
	{"pip cache", "pip", ".cache/pip", []string{"pip", "cache", "purge"}},
}

// **これらは消しても再取得できる。** ブラウザ自動化のバイナリとビルドキャッシュ。
var pathTargets = []pathTarget{
	{"puppeteer cache", ".cache/puppeteer"},
	{"playwright cache", ".cache/ms-playwright"},
	{"node-gyp cache", ".cache/node-gyp"},
	{"pnpm cache", ".cache/pnpm"},
}

// SelectUnusedStores は削除してよい pnpm store を選ぶ。
//
// **現行 store は絶対に消さない。** 中身が使われているので、消すと
// node_modules のハードリンクが全部切れる。パスの比較は末尾スラッシュを
// 落として行う（`pnpm store path` は末尾を付けないが、走査側は付きうる）。
func SelectUnusedStores(current string, all []string) (keep []string, remove []string) {
	cur := normPath(current)
	sorted := append([]string(nil), all...)
	sort.Strings(sorted)
	for _, s := range sorted {
		if cur != "" && normPath(s) == cur {
			keep = append(keep, s)
			continue
		}
		remove = append(remove, s)
	}
	return keep, remove
}

func normPath(p string) string {
	if p == "" {
		return ""
	}
	return filepath.Clean(strings.TrimSuffix(p, "/"))
}

// Run は掃除を実行する（Execute が偽なら表示のみ）。
func Run(ctx context.Context, r execx.Runner, cfg Config, w IO) int {
	c := newPalette(cfg.Color)
	out := w.out()

	section := func(title string) {
		fmt.Fprintf(out, "\n%s%s== %s ==%s\n", c.bold, c.cyan, title, c.reset)
	}

	mode := c.yellow + "DRY-RUN（試走／削除しません）" + c.reset
	if cfg.Execute {
		mode = c.green + "EXECUTE（実削除）" + c.reset
	}
	fmt.Fprintf(out, "%sWSL2 cleanup%s  mode: %s\n", c.bold, c.reset, mode)
	fmt.Fprintln(out, "実行前の全体サイズ:")
	fmt.Fprintf(out, "  ~        : %s\n", humanSize(ctx, r, cfg.Home))
	fmt.Fprintf(out, "  ~/.cache : %s\n", humanSize(ctx, r, filepath.Join(cfg.Home, ".cache")))

	var freed []string

	section("パッケージマネージャ キャッシュ")
	for _, t := range cmdTargets {
		cleanCmd(ctx, r, cfg, c, w, t)
	}

	section("ブラウザ自動化・ビルドキャッシュ")
	for _, t := range pathTargets {
		if s := cleanPath(ctx, r, cfg, c, w, t.label, filepath.Join(cfg.Home, t.rel)); s != "" {
			freed = append(freed, s)
		}
	}

	section("未使用 pnpm store (store/v*)")
	freed = append(freed, cleanPnpmStores(ctx, r, cfg, c, w)...)

	section("実行後のサイズ")
	fmt.Fprintf(out, "  du -sh ~                      → %s\n", humanSize(ctx, r, cfg.Home))
	fmt.Fprintf(out, "  du -sh ~/.cache               → %s\n",
		humanSizeOrDash(ctx, r, filepath.Join(cfg.Home, ".cache")))
	fmt.Fprintf(out, "  du -sh ~/.local/share/pnpm    → %s\n",
		humanSizeOrDash(ctx, r, filepath.Join(cfg.Home, ".local/share/pnpm")))
	fmt.Fprintln(out, "  df -h /:")
	if res, err := r.Run(ctx, execx.Cmd{Name: "df", Args: []string{"-h", "/"}}); err == nil {
		for _, line := range strings.Split(strings.TrimSuffix(res.Stdout, "\n"), "\n") {
			fmt.Fprintf(out, "    %s\n", line)
		}
	}

	if cfg.Execute && len(freed) > 0 {
		section("削除した項目")
		for _, item := range freed {
			fmt.Fprintf(out, "  - %s\n", item)
		}
	}

	section("次のステップ: ext4.vhdx の圧縮（Windows 側で手動）")
	fmt.Fprint(out, vhdxGuidance)

	if !cfg.Execute {
		fmt.Fprintf(out, "\n%sこれは dry-run です。実際に削除するには --execute を付けて再実行してください。%s\n",
			c.yellow, c.reset)
	}
	return 0
}

// cleanPath は1つのパスを掃除する。削除した場合は「ラベル: サイズ」を返す。
func cleanPath(ctx context.Context, r execx.Runner, cfg Config, c palette, w IO, label, path string) string {
	out := w.out()
	if _, err := os.Lstat(path); err != nil {
		fmt.Fprintf(out, "  [skip] %s: 見つかりません (%s)\n", label, path)
		return ""
	}
	size := humanSize(ctx, r, path)
	if size == "" {
		size = "?"
	}
	fmt.Fprintf(out, "  %s: %s%s%s  (%s)\n", label, c.bold, size, c.reset, path)

	if !cfg.Execute {
		fmt.Fprintf(out, "    %s(dry-run: 削除しません)%s\n", c.yellow, c.reset)
		return ""
	}
	if err := os.RemoveAll(path); err != nil {
		fmt.Fprintf(w.err(), "    %s削除に失敗しました（権限/ロック?）%s\n", c.yellow, c.reset)
		return ""
	}
	fmt.Fprintf(out, "    %s削除しました%s（約 %s 解放）\n", c.green, c.reset, size)
	return fmt.Sprintf("%s: %s", label, size)
}

// cleanCmd はコマンド経由の掃除。
func cleanCmd(ctx context.Context, r execx.Runner, cfg Config, c palette, w IO, t cmdTarget) {
	out := w.out()
	if !hasCommand(ctx, r, t.bin) {
		fmt.Fprintf(out, "  [skip] %s: '%s' コマンドが無いためスキップ\n", t.label, t.bin)
		return
	}

	hint := ""
	if t.cacheHint != "" {
		hint = filepath.Join(cfg.Home, t.cacheHint)
	}
	if hint != "" {
		if _, err := os.Lstat(hint); err == nil {
			fmt.Fprintf(out, "  %s: %s%s%s  (%s)\n", t.label, c.bold, humanSize(ctx, r, hint), c.reset, hint)
		} else {
			fmt.Fprintf(out, "  %s: (サイズ未測定 / コマンド内部で処理)\n", t.label)
		}
	} else {
		fmt.Fprintf(out, "  %s: (サイズ未測定 / コマンド内部で処理)\n", t.label)
	}

	joined := strings.Join(t.args, " ")
	if !cfg.Execute {
		fmt.Fprintf(out, "    %s(dry-run: 実行しません)%s  → %s\n", c.yellow, c.reset, joined)
		return
	}
	res, err := r.Run(ctx, execx.Cmd{Name: t.args[0], Args: t.args[1:]})
	if err != nil || !res.OK() {
		fmt.Fprintf(w.err(), "    %s実行に失敗しました%s: %s\n", c.yellow, c.reset, joined)
		return
	}
	fmt.Fprintf(out, "    %s実行しました%s: %s\n", c.green, c.reset, joined)
}

// cleanPnpmStores は現行以外の store/v* を掃除する。
func cleanPnpmStores(ctx context.Context, r execx.Runner, cfg Config, c palette, w IO) []string {
	out := w.out()
	root := filepath.Join(cfg.Home, ".local/share/pnpm/store")

	if !hasCommand(ctx, r, "pnpm") {
		fmt.Fprintln(out, "  [skip] pnpm コマンドが無いためスキップ")
		return nil
	}
	if st, err := os.Stat(root); err != nil || !st.IsDir() {
		fmt.Fprintf(out, "  [skip] store ディレクトリが見つかりません (%s)\n", root)
		return nil
	}

	current := ""
	if res, err := r.Run(ctx, execx.Cmd{Name: "pnpm", Args: []string{"store", "path"}}); err == nil && res.OK() {
		current = strings.TrimSpace(res.Stdout)
	}
	shown := current
	if shown == "" {
		shown = "取得失敗"
	}
	fmt.Fprintf(out, "  現行 store: %s%s%s\n", c.green, shown, c.reset)

	matches, _ := filepath.Glob(filepath.Join(root, "v*"))
	var dirs []string
	for _, m := range matches {
		if st, err := os.Stat(m); err == nil && st.IsDir() {
			dirs = append(dirs, m)
		}
	}

	keep, remove := SelectUnusedStores(current, dirs)
	var freed []string
	// 表示順は辞書順（走査順に依存しない）
	for _, s := range mergeSorted(keep, remove) {
		if contains(keep, s) {
			fmt.Fprintf(out, "  [keep] %s: 現行 store のため保持  (%s)\n",
				filepath.Base(s), humanSize(ctx, r, s))
			continue
		}
		if f := cleanPath(ctx, r, cfg, c, w, "未使用 store "+filepath.Base(s), s); f != "" {
			freed = append(freed, f)
		}
	}
	return freed
}

func mergeSorted(a, b []string) []string {
	out := append(append([]string(nil), a...), b...)
	sort.Strings(out)
	return out
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}

func hasCommand(ctx context.Context, r execx.Runner, name string) bool {
	res, err := r.Run(ctx, execx.Cmd{Name: "command", Args: []string{"-v", name}})
	if err == nil && res.OK() {
		return true
	}
	// command が使えない Runner でも判定できるようにする
	if _, lerr := lookPath(name); lerr == nil {
		return true
	}
	return false
}

// humanSize は `du -sh` の1列目を返す（測れなければ空）。
func humanSize(ctx context.Context, r execx.Runner, path string) string {
	res, err := r.Run(ctx, execx.Cmd{Name: "du", Args: []string{"-sh", path}})
	if err != nil || !res.OK() {
		return ""
	}
	fields := strings.Fields(res.Stdout)
	if len(fields) == 0 {
		return ""
	}
	return fields[0]
}

func humanSizeOrDash(ctx context.Context, r execx.Runner, path string) string {
	if s := humanSize(ctx, r, path); s != "" {
		return s
	}
	return "-"
}

const vhdxGuidance = `  WSL2 のディスクイメージ (ext4.vhdx) は、中で削除しても自動では縮みません。
  実ディスクの空きを取り戻すには Windows 側で圧縮します。

  1. PowerShell を「管理者として実行」で開く
  2. WSL を停止:
       wsl --shutdown
  3. diskpart を起動して圧縮:
       diskpart
       select vdisk file="C:\Users\<ユーザー名>\AppData\Local\Packages\<ディストロのパッケージ名>\LocalState\ext4.vhdx"
       attach vdisk readonly
       compact vdisk
       detach vdisk
       exit

  ※ vhdx の場所が不明な場合（PowerShell）:
       (Get-ChildItem -Path $env:LOCALAPPDATA\Packages -Recurse -Filter ext4.vhdx -ErrorAction SilentlyContinue).FullName
`
