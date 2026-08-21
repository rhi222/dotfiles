package doctor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// RepoState は1リポジトリ分の「ローカル専用の作業状態」。
type RepoState struct {
	Path string
	// Remotes は remote の数。**0 なら push で逃がせない**（コピーしないと
	// 履歴ごと消える）。
	Remotes int
	// Unpushed はどの remote にも無いコミット数（全ブランチ）。
	Unpushed int
	Stash    int
	Dirty    int
	Worktree int
}

// HasLocalWork は再clone で戻らないものが残っているか。
func (s RepoState) HasLocalWork() bool {
	return s.Remotes == 0 || s.Unpushed > 0 || s.Stash > 0 || s.Dirty > 0 || s.Worktree > 0
}

// Line は報告用の1行（Shell 版と同じ体裁）。
func (s RepoState) Line() string {
	line := "== " + s.Path + " "
	if s.Remotes == 0 {
		line += " remote:なし"
	}
	line += fmt.Sprintf(" unpushed:%d stash:%d dirty:%d worktree:%d",
		s.Unpushed, s.Stash, s.Dirty, s.Worktree)
	return line
}

// InspectRepo は1リポジトリの状態を集める。git リポジトリでなければ false。
func InspectRepo(ctx context.Context, r execx.Runner, path string) (RepoState, bool) {
	git := func(args ...string) (string, bool) {
		res, err := r.Run(ctx, execx.Cmd{Name: "git", Args: append([]string{"-C", path}, args...)})
		if err != nil || !res.OK() {
			return "", false
		}
		return res.Stdout, true
	}

	if _, ok := git("rev-parse", "--git-dir"); !ok {
		return RepoState{}, false
	}

	s := RepoState{Path: path}
	if out, ok := git("remote"); ok {
		s.Remotes = countLines(out)
	}
	if out, ok := git("log", "--branches", "--not", "--remotes", "--oneline"); ok {
		s.Unpushed = countLines(out)
	}
	if out, ok := git("stash", "list"); ok {
		s.Stash = countLines(out)
	}
	if out, ok := git("status", "--porcelain"); ok {
		s.Dirty = countLines(out)
	}
	if out, ok := git("worktree", "list"); ok {
		// 先頭はメイン worktree なので数えない
		if n := countLines(out); n > 0 {
			s.Worktree = n - 1
		}
	}
	return s, true
}

func countLines(s string) int {
	s = strings.TrimSuffix(s, "\n")
	if s == "" {
		return 0
	}
	return strings.Count(s, "\n") + 1
}

// ListTargets は点検対象のリポジトリを返す。
//
// 引数があればそれを、無ければ ghq の一覧とホーム直下（隠しディレクトリ配下を
// 除く）の野良リポジトリを並べる。
func ListTargets(ctx context.Context, r execx.Runner, home string, args []string) ([]string, error) {
	if len(args) > 0 {
		return args, nil
	}

	res, err := r.Run(ctx, execx.Cmd{Name: "ghq", Args: []string{"list", "-p"}})
	if err != nil || !res.OK() {
		return nil, fmt.Errorf("ghq が見つかりません。対象ディレクトリを引数で渡してください")
	}
	out := splitLines(res.Stdout)

	// ホーム直下の野良リポジトリ（深さ2まで、隠しディレクトリ配下は除く）
	entries, rerr := os.ReadDir(home)
	if rerr == nil {
		for _, e := range entries {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			cand := filepath.Join(home, e.Name())
			if _, serr := os.Stat(filepath.Join(cand, ".git")); serr == nil {
				out = append(out, cand)
			}
		}
	}
	return out, nil
}

// CheckMigration は対象リポジトリを点検して報告する。
// 終了コードは 0 = 全部きれい / 1 = 作業状態が残るリポジトリあり。
func CheckMigration(ctx context.Context, r execx.Runner, home string, args []string, w IO) int {
	targets, err := ListTargets(ctx, r, home, args)
	if err != nil {
		fmt.Fprintf(w.Stderr, "ERROR: %v\n", err)
		return 2
	}

	total, found := 0, 0
	for _, path := range targets {
		if path == "" {
			continue
		}
		s, ok := InspectRepo(ctx, r, path)
		if !ok {
			continue
		}
		total++
		if s.HasLocalWork() {
			found++
			fmt.Fprintln(w.out(), s.Line())
		}
	}

	fmt.Fprintln(w.out(), "---")
	fmt.Fprintf(w.out(), "%d/%d リポジトリにローカル専用の作業状態がある\n", found, total)
	if found == 0 {
		return 0
	}
	return 1
}
