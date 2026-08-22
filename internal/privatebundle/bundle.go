// Package private は gitignore しているローカル設定・機密ファイルを
// 1ディレクトリに集約し、端末間で運ぶ。
//
// **集約先が実体で、各所へは dotfilesLink.sh が symlink を張る。**
// どこを編集しても集約先が最新になるので、export はいつ走らせてもよい。
//
// 移植対象の宣言（Entries）はこのパッケージだけが持つ。dotfilesLink.sh は
// 「集約先にあるものを配る」しか知らないので、対象が増えても向こうは変わらない。
package privatebundle

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Kind は相対パスの起点。
type Kind int

const (
	// Home は $HOME 起点。
	Home Kind = iota
	// Repo はリポジトリ起点。
	Repo
)

func (k Kind) String() string {
	if k == Home {
		return "home"
	}
	return "repo"
}

// Entry は移植対象1件。
type Entry struct {
	Kind Kind
	// Rel は起点からの相対パス。
	Rel string
	// Under が真なら「そのディレクトリ直下のうち git が ignore しているもの」を拾う。
	//
	// **passwords/ がこれ。** README.md と .gitkeep が追跡対象で中身だけが
	// ignore され、子の名前は端末ごとに違いうるのでハードコードしない。
	Under bool
}

// Entries は移植対象の宣言。
//
// **パスに社内名を含むものは既に .gitignore に書かれている。** この一覧を
// public に置いても新たな漏洩は起きない。
var Entries = []Entry{
	{Home, ".claude/local-context.md", false},
	{Home, ".config/linear/api-key", false},
	{Home, ".config/dotfiles/secret-patterns.txt", false},
	{Repo, ".config/git/config-local", false},
	{Repo, ".config/git/config-work", false},
	{Repo, ".config/fish/my/conf.d/99-local.fish", false},
	{Repo, ".config/nvim/lua/my/local_config.lua", false},
	{Repo, ".config/claude/skills/cross-repo-investigate/repos.yml", false},
	{Repo, ".config/claude/skills/esa-weekly-report/esa-weekly-report-posts.json", false},
	{Repo, ".config/claude/skills/cross-repo-auto-discover", false},
	{Repo, ".config/AutoHotkey/ahk-snippets/js", false},
	{Repo, ".config/AutoHotkey/scripts/snippets-local.ahk", false},
	{Repo, ".config/AutoHotkey/ahk-snippets/passwords", true},
}

// Config は集約1回分の設定。
type Config struct {
	// PrivateDir は集約先（既定 ~/.local/share/dotfiles-private）。
	PrivateDir string
	// Home は $HOME。
	Home string
	// RepoDir はリポジトリのルート。
	RepoDir string
	// ZipPassword はテスト専用。zip -e の代わりに -P を使う
	// （-P は平文が ps に乗るので実運用では使わない）。
	ZipPassword string
	// Today は既定の出力名に入れる日付。
	Today string
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

// root は Kind に対応する起点を返す。
func (c Config) root(k Kind) string {
	if k == Home {
		return c.Home
	}
	return c.RepoDir
}

// src は実体が置かれる（べき）場所。
func (c Config) src(k Kind, rel string) string { return filepath.Join(c.root(k), rel) }

// dst は集約先での場所。
func (c Config) dst(k Kind, rel string) string {
	return filepath.Join(c.PrivateDir, k.String(), rel)
}

// ignoredChildren はディレクトリ直下のうち git が ignore しているものを返す。
//
// **追跡ファイル（README.md 等）を巻き込まないための判定。**
func ignoredChildren(ctx context.Context, r execx.Runner, repoDir, dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		res, rerr := r.Run(ctx, execx.Cmd{
			Name: "git",
			Args: []string{"-C", repoDir, "check-ignore", "-q", filepath.Join(dir, e.Name())},
		})
		if rerr == nil && res.OK() {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out
}

// bundleChildren は集約先の直下の名前を返す（ignore 判定を通さない版）。
func bundleChildren(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		out = append(out, e.Name())
	}
	sort.Strings(out)
	return out
}

// expand は宣言を「実際に見るべき (kind, rel) の並び」へ広げる。
//
// under の項目は、**集約先とリポジトリ側の両方から子を集める**
// （片方にしか無い状態も出したいため）。
func expand(ctx context.Context, r execx.Runner, cfg Config, e Entry, includeBundle bool) []Entry {
	if !e.Under {
		return []Entry{e}
	}
	names := ignoredChildren(ctx, r, cfg.RepoDir, cfg.src(e.Kind, e.Rel))
	if includeBundle {
		names = append(names, bundleChildren(cfg.dst(e.Kind, e.Rel))...)
	}
	sort.Strings(names)

	var out []Entry
	seen := map[string]bool{}
	for _, n := range names {
		if seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, Entry{Kind: e.Kind, Rel: filepath.Join(e.Rel, n)})
	}
	return out
}

// HardenPermissions は集約先を 700/600 に締める。
//
// **zip の保存内容に頼らず張り直す。** Windows 側で開いて再圧縮すると Unix 属性が
// 落ち、api-key が 644 で復元される。
//
// **symlink は触らない。** os.Chmod は symlink を辿るので、辿ると集約先の外の
// 実体（repos.yml の参照先など）の権限まで変えてしまう。
func HardenPermissions(dir string) error {
	if err := os.Chmod(dir, 0o700); err != nil {
		return err
	}
	return filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if d.IsDir() {
			return os.Chmod(path, 0o700)
		}
		if d.Type().IsRegular() {
			return os.Chmod(path, 0o600)
		}
		return nil
	})
}

// AdoptCounts は adopt の集計。
type AdoptCounts struct {
	Moved   int
	Skipped int
	Missing int
}

// Adopt は散らばった実体を集約先へ移し、元の場所に symlink を張る。
// **旧環境で1回だけ走らせる移行コマンドなので、既定は dry-run。**
func Adopt(ctx context.Context, r execx.Runner, cfg Config, execute bool, w IO) int {
	var c AdoptCounts
	rc := 0

	for _, decl := range Entries {
		for _, e := range expand(ctx, r, cfg, decl, false) {
			if !adoptOne(cfg, e, execute, &c, w) {
				rc = 1
			}
		}
	}

	fmt.Fprintln(w.out(), "---")
	if !execute {
		fmt.Fprintln(w.out(), "dry-run です。実行するには --execute を付けてください")
		return rc
	}
	// **集約先は資格情報を1箇所に集めたディレクトリなので、作った直後に締める。**
	// import 側だけでハードニングすると、集約した端末では 755 のまま残る。
	if st, err := os.Stat(cfg.PrivateDir); err == nil && st.IsDir() {
		if herr := HardenPermissions(cfg.PrivateDir); herr != nil {
			fmt.Fprintf(w.err(), "[FAIL] パーミッションの設定に失敗しました: %v\n", herr)
			rc = 1
		}
	}
	fmt.Fprintf(w.out(), "移動: %d 件 / 既に symlink: %d 件 / 不在: %d 件\n", c.Moved, c.Skipped, c.Missing)
	return rc
}

func adoptOne(cfg Config, e Entry, execute bool, c *AdoptCounts, w IO) bool {
	src := cfg.src(e.Kind, e.Rel)
	dst := cfg.dst(e.Kind, e.Rel)

	fi, lerr := os.Lstat(src)
	if lerr == nil && fi.Mode()&os.ModeSymlink != 0 {
		fmt.Fprintf(w.out(), "[SKIP] %s は既に symlink です\n", e.Rel)
		c.Skipped++
		return true
	}
	if lerr != nil {
		fmt.Fprintf(w.out(), "[MISS] %s がありません（この端末で使っていなければ問題ありません）\n", e.Rel)
		c.Missing++
		return true
	}
	if !execute {
		fmt.Fprintf(w.out(), "[DRY-RUN] %s を %s へ移して symlink を張ります\n", src, dst)
		return true
	}

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		fmt.Fprintf(w.err(), "[FAIL] %s の移動に失敗しました\n", e.Rel)
		return false
	}
	if err := os.Rename(src, dst); err != nil {
		fmt.Fprintf(w.err(), "[FAIL] %s の移動に失敗しました\n", e.Rel)
		return false
	}
	if err := os.Symlink(dst, src); err != nil {
		fmt.Fprintf(w.err(), "[FAIL] %s の symlink 作成に失敗しました\n", e.Rel)
		return false
	}
	fmt.Fprintf(w.out(), "[OK] %s\n", e.Rel)
	c.Moved++
	return true
}

// Export は集約先をパスワード付き zip に固める。
//
// **zip コマンドを呼ぶ。** Go 標準ライブラリの archive/zip は暗号化を扱えず、
// 外部 module を入れるのは初期実装の方針から外れる。
func Export(ctx context.Context, r execx.Runner, cfg Config, out string, w IO) int {
	if st, err := os.Stat(cfg.PrivateDir); err != nil || !st.IsDir() {
		fmt.Fprintf(w.err(), "[FAIL] 集約先がありません: %s\n", cfg.PrivateDir)
		fmt.Fprintln(w.err(), "       先に adopt --execute を実行してください")
		return 1
	}

	if out == "" {
		out = filepath.Join(cfg.Home, fmt.Sprintf("dotfiles-private-%s.zip",
			strings.ReplaceAll(cfg.Today, "-", "")))
	}
	if !filepath.IsAbs(out) {
		wd, _ := os.Getwd()
		out = filepath.Join(wd, out)
	}
	if _, err := os.Lstat(out); err == nil {
		fmt.Fprintf(w.err(), "[FAIL] 既に存在します: %s\n", out)
		return 1
	}

	// **-y は必須。** 無いと集約先の symlink を辿って実体化し、repos.yml が2つになる。
	// 実体化しても「中身が読める」テストは通ってしまうので、symlink であること
	// 自体を検査する回帰テストを置いている。
	args := []string{"-r", "-y", "-q"}
	args = append(args, zipCryptArgs(cfg)...)
	args = append(args, out, ".", "-x", "*.DS_Store", "*~", "*.swp")

	res, err := r.Run(ctx, execx.Cmd{Name: "zip", Args: args, Dir: cfg.PrivateDir})
	if err != nil || !res.OK() {
		fmt.Fprintln(w.err(), "[FAIL] zip の作成に失敗しました")
		_ = os.Remove(out)
		return 1
	}
	if err := os.Chmod(out, 0o600); err != nil {
		fmt.Fprintf(w.err(), "[FAIL] パーミッションの設定に失敗しました: %v\n", err)
		return 1
	}
	fmt.Fprintf(w.out(), "[OK] %s\n", out)
	fmt.Fprintln(w.out(), "     新環境で: bash scripts/private-bundle.sh import <このzip>")
	return 0
}

func zipCryptArgs(cfg Config) []string {
	if cfg.ZipPassword != "" {
		return []string{"-P", cfg.ZipPassword}
	}
	return []string{"-e"}
}

// Import は zip を集約先へ展開する。
func Import(ctx context.Context, r execx.Runner, cfg Config, zipfile string, force bool, w IO) int {
	if st, err := os.Stat(zipfile); err != nil || st.IsDir() {
		fmt.Fprintf(w.err(), "[FAIL] zip がありません: %s\n", zipfile)
		return 1
	}
	if _, err := os.Lstat(cfg.PrivateDir); err == nil && !force {
		fmt.Fprintf(w.err(), "[FAIL] 集約先が既に存在します: %s\n", cfg.PrivateDir)
		fmt.Fprintln(w.err(), "       上書きしてよければ --force を付けてください")
		return 1
	}

	if err := os.MkdirAll(cfg.PrivateDir, 0o755); err != nil {
		fmt.Fprintf(w.err(), "[FAIL] 集約先を作れません: %v\n", err)
		return 1
	}

	// unzip の暗号化オプションは -P だけ（-e は zip 側の対話指定なので落とす）
	args := []string{"-q", "-o"}
	if cfg.ZipPassword != "" {
		args = append(args, "-P", cfg.ZipPassword)
	}
	args = append(args, zipfile, "-d", cfg.PrivateDir)

	res, err := r.Run(ctx, execx.Cmd{Name: "unzip", Args: args})
	if err != nil || !res.OK() {
		fmt.Fprintln(w.err(), "[FAIL] 展開に失敗しました（パスワードを確認してください）")
		return 1
	}
	if herr := HardenPermissions(cfg.PrivateDir); herr != nil {
		fmt.Fprintf(w.err(), "[FAIL] パーミッションの設定に失敗しました: %v\n", herr)
		return 1
	}
	fmt.Fprintf(w.out(), "[OK] %s に展開しました\n", cfg.PrivateDir)
	fmt.Fprintln(w.out(), "     次に ./dotfilesLink.sh を実行してください")
	return 0
}

// StatusKind は status の分類。
type StatusKind int

const (
	// Linked は集約先へ symlink が張られている。
	Linked StatusKind = iota
	// Unlinked は実体があるが symlink になっていない。
	Unlinked
	// Broken は symlink があるのに参照先が無い。
	Broken
	// Absent は集約先に無い（旧環境からのコピーか手書きが必要）。
	Absent
)

// Classify は1件の状態を分類する。副作用は無い。
//
// **リンク切れを最初に見る。** 実体が消えたうえに dangling symlink が残って
// いる状態は「集約先に無い」にも当てはまるが、手を打つ必要があるのは
// リンク切れのほうなので、そちらへ寄せる。
func Classify(srcIsSymlink, srcResolves, dstExists bool) StatusKind {
	switch {
	case srcIsSymlink && !srcResolves:
		return Broken
	case !dstExists:
		return Absent
	case srcIsSymlink:
		return Linked
	default:
		return Unlinked
	}
}

// Status は宣言を基準に状態を報告する。
//
// **集約先の走査だけだと「集約先に無い＝旧環境からのコピーがまだ」を
// 検出できない**ので、宣言（Entries）を基準にする。
func Status(ctx context.Context, r execx.Runner, cfg Config, w IO) int {
	if st, err := os.Stat(cfg.PrivateDir); err != nil || !st.IsDir() {
		fmt.Fprintf(w.out(), "集約先がありません: %s\n", cfg.PrivateDir)
		fmt.Fprintln(w.out(), "  旧環境があるなら: bash scripts/private-bundle.sh import <zip>")
		fmt.Fprintln(w.out(), "  無いなら雛形生成にフォールバックします（./dotfilesLink.sh）")
		return 0
	}

	fmt.Fprintf(w.out(), "集約先: %s\n", cfg.PrivateDir)
	fmt.Fprintln(w.out(), "")

	groups := map[StatusKind][]string{}
	for _, decl := range Entries {
		for _, e := range expand(ctx, r, cfg, decl, true) {
			src := cfg.src(e.Kind, e.Rel)
			dst := cfg.dst(e.Kind, e.Rel)

			fi, lerr := os.Lstat(src)
			isLink := lerr == nil && fi.Mode()&os.ModeSymlink != 0
			resolves := false
			if isLink {
				_, serr := os.Stat(src)
				resolves = serr == nil
			}
			_, derr := os.Lstat(dst)

			switch Classify(isLink, resolves, derr == nil) {
			case Broken:
				groups[Broken] = append(groups[Broken], src)
			case Absent:
				groups[Absent] = append(groups[Absent], filepath.Join(e.Kind.String(), e.Rel))
			case Linked:
				groups[Linked] = append(groups[Linked], src)
			default:
				groups[Unlinked] = append(groups[Unlinked], src)
			}
		}
	}

	printGroup(w, "リンク済み", "", groups[Linked])
	printGroup(w, "未リンク", "./dotfilesLink.sh を実行してください", groups[Unlinked])
	printGroup(w, "リンク切れ", "集約先から実体が消えています", groups[Broken])
	printGroup(w, "集約先に無い", "旧環境からのコピーか手書きが必要", groups[Absent])
	return 0
}

func printGroup(w IO, label, hint string, items []string) {
	if hint != "" {
		fmt.Fprintf(w.out(), "%s (%d)  ← %s\n", label, len(items), hint)
	} else {
		fmt.Fprintf(w.out(), "%s (%d)\n", label, len(items))
	}
	for _, it := range items {
		fmt.Fprintf(w.out(), "  %s\n", it)
	}
	fmt.Fprintln(w.out(), "")
}
