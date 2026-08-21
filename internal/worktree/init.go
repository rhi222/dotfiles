package worktree

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

// InitConfig は worktree 作成後の初期化1回分の設定。
type InitConfig struct {
	// Target は初期化する worktree のパス。
	Target string
	// DryRun なら何も変更せず、やることだけを出す。
	DryRun bool
	// InitDir はリポジトリ固有スクリプトの置き場（既定 scripts/worktree-init.d）。
	InitDir string
}

// InitIO は出力先。
type InitIO struct {
	Stdout io.Writer
	Stderr io.Writer
}

// 掘らないディレクトリ。**node_modules を掘ると依存の中の .env を拾い、
// 数千件を check-ignore に掛けることになる。**
var initSkipDirs = map[string]bool{
	"node_modules": true,
	".wt":          true,
	".git":         true,
}

// normalizeRepoKey は origin URL をリポジトリ固有スクリプトの探索キーへ正規化する。
//
//	git@github.com:owner/repo.git       -> github.com/owner/repo
//	https://github.com/owner/repo.git   -> github.com/owner/repo
//	ssh://git@github.com/owner/repo.git -> github.com/owner/repo
//
// **形式によって食い違うと「同じリポジトリなのに端末によってフックが走らない」**
// が起きるので、どの書き方でも同じキーになるようにする。
func normalizeRepoKey(url string) string {
	for _, p := range []string{"ssh://", "https://", "http://", "git://"} {
		url = strings.TrimPrefix(url, p)
	}
	// user@ を落とす（scp 形式・ssh 形式）。最初の @ まで
	if i := strings.Index(url, "@"); i >= 0 {
		url = url[i+1:]
	}
	// scp 形式の最初の ':' を '/' にする
	url = strings.Replace(url, ":", "/", 1)
	return strings.TrimSuffix(url, ".git")
}

// installCommand は lock ファイルから依存インストールのコマンドを決める。
// **優先順に意味がある**（pnpm と npm の lock が両方ある移行中のリポジトリで
// pnpm を選ぶ）。lock が無ければ空文字。
func installCommand(target string) string {
	for _, c := range []struct{ lock, cmd string }{
		{"pnpm-lock.yaml", "pnpm install"},
		{"package-lock.json", "npm ci"},
		{"yarn.lock", "yarn install"},
	} {
		if _, err := os.Stat(filepath.Join(target, c.lock)); err == nil {
			return c.cmd
		}
	}
	return ""
}

// collectEnvFiles は root 配下の .env* を repo 相対パスで返す（辞書順）。
//
// **並びは辞書順に固定する。** Shell 版は find のファイルシステム順なので
// 出力順が端末ごとに変わりうる。決定的なほうが差分を読める。
func collectEnvFiles(root string) []string {
	var out []string
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return fs.SkipDir
		}
		if d.IsDir() {
			if path != root && initSkipDirs[d.Name()] {
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasPrefix(d.Name(), ".env") {
			return nil
		}
		rel, rerr := filepath.Rel(root, path)
		if rerr == nil {
			out = append(out, rel)
		}
		return nil
	})
	sort.Strings(out)
	return out
}

// Init は worktree 作成後の初期化を行う。
//
//  1. メイン worktree の gitignore 対象 .env* を相対パスを保ってコピー
//  2. lock ファイルを判定して依存をインストール
//  3. リポジトリ固有スクリプトがあれば実行（失敗しても継続）
func Init(ctx context.Context, r execx.Runner, cfg InitConfig, w InitIO) int {
	out, errOut := w.Stdout, w.Stderr
	if out == nil {
		out = io.Discard
	}
	if errOut == nil {
		errOut = io.Discard
	}

	git := func(args ...string) (execx.Result, bool) {
		res, err := r.Run(ctx, execx.Cmd{Name: "git", Args: append([]string{"-C", cfg.Target}, args...)})
		return res, err == nil && res.OK()
	}

	if _, ok := git("rev-parse", "--is-inside-work-tree"); !ok {
		fmt.Fprintf(errOut, "error: gitリポジトリ内ではありません: %s\n", cfg.Target)
		return 1
	}

	gitDir, ok1 := git("rev-parse", "--path-format=absolute", "--git-dir")
	commonDir, ok2 := git("rev-parse", "--path-format=absolute", "--git-common-dir")
	if !ok1 || !ok2 {
		fmt.Fprintf(errOut, "error: gitリポジトリ内ではありません: %s\n", cfg.Target)
		return 1
	}
	gd := strings.TrimSpace(gitDir.Stdout)
	cd := strings.TrimSpace(commonDir.Stdout)

	// **メイン worktree では走らせない。** .env をコピーしても意味が無く、
	// 依存インストールが本体を触ってしまう。
	if gd == cd {
		fmt.Fprintf(errOut, "error: メインworktreeです。linked worktree内で実行してください: %s\n", cfg.Target)
		return 1
	}

	// common_dir は <メイン worktree>/.git を指す
	mainWorktree := filepath.Dir(cd)
	if _, err := os.Lstat(filepath.Join(mainWorktree, ".git")); err != nil {
		fmt.Fprintln(errOut, "error: メインworktreeを特定できません（bare repository?）")
		return 1
	}

	if code := copyEnvFiles(ctx, r, cfg, mainWorktree, out, errOut); code != 0 {
		return code
	}
	installDeps(ctx, r, cfg, out, errOut)
	runCustomHook(ctx, r, cfg, out, errOut)
	return 0
}

func copyEnvFiles(ctx context.Context, r execx.Runner, cfg InitConfig, mainWorktree string, out, errOut io.Writer) int {
	for _, rel := range collectEnvFiles(mainWorktree) {
		// tracked なファイル（.env.example 等）は check-ignore に該当しないので除外される。
		// **追跡されているものは worktree に既にあるのでコピーは不要。**
		res, err := r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", mainWorktree, "check-ignore", "-q", rel},
		})
		if err != nil || !res.OK() {
			continue
		}

		dst := filepath.Join(cfg.Target, rel)
		if _, err := os.Lstat(dst); err == nil {
			fmt.Fprintf(out, "skip (既存): %s\n", rel)
			continue
		}
		if cfg.DryRun {
			fmt.Fprintf(out, "[dry-run] copy: %s\n", rel)
			continue
		}
		if err := copyPreservingMode(filepath.Join(mainWorktree, rel), dst); err != nil {
			fmt.Fprintf(errOut, "error: コピーに失敗: %s: %v\n", rel, err)
			return 1
		}
		fmt.Fprintf(out, "copy: %s\n", rel)
	}
	return 0
}

// copyPreservingMode は権限を保ってコピーする（cp -p 相当）。
// **.env は秘密を持つので、権限を落として配ってはいけない。**
func copyPreservingMode(src, dst string) error {
	st, err := os.Stat(src)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dst, data, st.Mode().Perm())
}

func installDeps(ctx context.Context, r execx.Runner, cfg InitConfig, out, errOut io.Writer) {
	cmd := installCommand(cfg.Target)
	switch {
	case cmd == "":
		fmt.Fprintln(out, "install: skip（lockファイルなし）")
	case cfg.DryRun:
		fmt.Fprintf(out, "[dry-run] install: %s\n", cmd)
	default:
		fmt.Fprintf(out, "install: %s\n", cmd)
		parts := strings.Fields(cmd)
		res, err := r.Run(ctx, execx.Cmd{Name: parts[0], Args: parts[1:], Dir: cfg.Target})
		WriteIndented(out, res.Stdout)
		if err != nil || !res.OK() {
			WriteIndented(errOut, res.Stderr)
		}
	}
}

func runCustomHook(ctx context.Context, r execx.Runner, cfg InitConfig, out, errOut io.Writer) {
	res, err := r.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"-C", cfg.Target, "remote", "get-url", "origin"},
	})
	origin := ""
	if err == nil && res.OK() {
		origin = strings.TrimSpace(res.Stdout)
	}
	if origin == "" {
		fmt.Fprintln(out, "custom: skip（origin未設定）")
		return
	}

	key := normalizeRepoKey(origin)
	script := filepath.Join(cfg.InitDir, key+".sh")
	if _, err := os.Stat(script); err != nil {
		fmt.Fprintf(out, "custom: skip（%s 用スクリプトなし）\n", key)
		return
	}
	if cfg.DryRun {
		fmt.Fprintf(out, "[dry-run] custom: %s\n", script)
		return
	}

	fmt.Fprintf(out, "custom: %s\n", script)
	// **固有スクリプトが失敗しても継続する。** 初期化の一部が失敗しただけで
	// worktree が使えなくなるほうが困る。
	hres, herr := r.Run(ctx, execx.Cmd{
		Name: "bash", Args: []string{script, cfg.Target}, Dir: cfg.Target,
	})
	WriteIndented(out, hres.Stdout)
	if herr != nil || !hres.OK() {
		fmt.Fprintf(errOut, "warning: custom hook が失敗しました（無視して継続）: %s\n", script)
	}
}
