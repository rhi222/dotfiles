package worktree

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// maxDepth は走査するディレクトリの深さ（Shell 版の find -maxdepth 4 と同じ）。
const maxDepth = 4

// Config は掃除1回分の設定。
type Config struct {
	// Roots は走査ルート（スペース区切り。表示にもそのまま使う）。
	Roots string
	// Repos を渡すと走査を省いてこのリポジトリだけを見る（テスト用）。
	Repos []string

	Force    bool
	ShowSize bool

	// PRStateCmd は PR 状態取得の差し替え口
	// （Shell 版の WORKTREE_CLEANUP_PR_STATE_CMD）。
	PRStateCmd string
}

// discoverRepos は走査ルート配下の（bare でない）git リポジトリを列挙する。
//
// **worktree の置き場所を決め打ちで走査しない。** リポジトリを見つけてから
// git worktree list に聞くことで、.wt/ / .claude/worktrees/ / /tmp /
// 旧 ~/git-worktrees/ をすべて拾える。
//
// **見つけたリポジトリの中は掘らない。** 掘ると worktree 内の .git（ファイル）や
// submodule を別リポジトリとして拾ってしまう（Shell 版の -prune と同じ）。
func discoverRepos(roots []string) []string {
	var out []string
	for _, root := range roots {
		if root == "" {
			continue
		}
		if st, err := os.Stat(root); err != nil || !st.IsDir() {
			continue
		}
		rootDepth := strings.Count(filepath.Clean(root), string(os.PathSeparator))

		_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return fs.SkipDir
			}
			if !d.IsDir() {
				return nil
			}
			if strings.Count(path, string(os.PathSeparator))-rootDepth > maxDepth {
				return fs.SkipDir
			}
			if d.Name() == ".git" {
				out = append(out, normPath(filepath.Dir(path)))
				// この .git を含むリポジトリの内側は掘らない
				return fs.SkipDir
			}
			return nil
		})
	}
	return out
}

// BuildPlan は観測して判定し、Plan を組み立てる。
//
// **1リポジトリの失敗で全体を止めない。** worktree 一覧が取れないリポジトリは
// 飛ばして次へ進む（Shell 版が set -e を使わない理由と同じ）。
func BuildPlan(ctx context.Context, r execx.Runner, cfg Config) *Plan {
	repos := cfg.Repos
	if repos == nil {
		repos = discoverRepos(strings.Fields(cfg.Roots))
	}

	p := &Plan{Roots: cfg.Roots}
	opt := Options{Force: cfg.Force}

	for _, repo := range repos {
		mainPath, ok := mainWorktreePath(ctx, r, repo)
		if !ok {
			continue
		}
		res, err := r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", repo, "worktree", "list", "--porcelain"},
		})
		if err != nil || !res.OK() {
			continue
		}

		rp := RepoPlan{Repo: repo}
		for _, e := range parseWorktrees(res.Stdout, mainPath) {
			obs := Observation{
				Repo:        repo,
				Path:        e.Path,
				Branch:      e.Branch,
				Locked:      e.Locked,
				LockDetail:  e.LockDetail,
				Prunable:    e.Prunable,
				PruneDetail: e.PruneDetail,
			}

			// **locked / prunable / detached では余分な観測をしない。** 判定に
			// 使わない情報のために git と gh を呼ぶのは無駄で、gh 未認証の端末で
			// 無意味に遅くなる。Classify の順序と対応している。
			if !e.Locked && !e.Prunable && e.Branch != "" {
				obs.HasTrackedChanges = hasTrackedChanges(ctx, r, e.Path)
				obs.UntrackedCount = untrackedCount(ctx, r, e.Path)
				obs.PR = prState(ctx, r, repo, e.Branch, cfg.PRStateCmd)
			}

			it := Item{Path: e.Path, Branch: e.Branch, Decision: Classify(obs, opt)}
			// 測定対象は DELETE 候補だけ（du は遅い）。
			if cfg.ShowSize && it.Decision.Verdict == DELETE {
				it.SizeKB = sizeKB(ctx, r, e.Path)
				p.FreedKB += it.SizeKB
			}
			rp.Items = append(rp.Items, it)
		}
		p.Repos = append(p.Repos, rp)
	}
	return p
}

// ExecOptions は実行時の出力先。
type ExecOptions struct {
	Stdout io.Writer
	Stderr io.Writer
	Color  bool
}

// Execute は Plan の DELETE を削除し、PRUNE があるリポジトリを掃除する。
// 個別の失敗では止まらず、件数を Plan へ書き戻す。
//
// **git の出力は握り潰さず利用者に見せる。** git worktree remove は
// ディレクトリ削除に失敗しても admin エントリを消すことがあり（孤児
// ディレクトリが残り、以降 git worktree list に出ないのでこのツールで
// 永久に検出できないゴミになる）、その失敗理由はまさに利用者が知るべき情報。
func Execute(ctx context.Context, r execx.Runner, p *Plan, opt ExecOptions) {
	p.Executed = true
	c := newPalette(opt.Color)
	out := opt.Stdout
	if out == nil {
		out = io.Discard
	}
	errOut := opt.Stderr
	if errOut == nil {
		errOut = io.Discard
	}

	dels := p.Deletions()
	if len(dels) > 0 {
		Section(out, opt.Color, "削除の実行")
	}
	for _, d := range dels {
		// **常に --force で remove する。** git worktree remove は未追跡ファイルが
		// 1つでもあると --force なしで exit 128 で拒否するため、未追跡のみの
		// MERGED を既定モードでも消せるようにするには常に要る。安全性は
		// Classify が担保していて、DELETE に到達するのは locked/prunable/detached
		// でなく、かつ追跡変更なし（または利用者が --force を指定した）ものだけ。
		//
		// -f -f（二重 force）は実装しない。locked は必ず SKIP されるので不要で、
		// locked を強制削除する手段はあえて持たせない。
		//
		// git -C はリポジトリ側を指す。削除対象の worktree 内を指すと cwd が消える。
		res, err := r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", d.Repo, "worktree", "remove", "--force", d.Path},
		})
		WriteIndented(out, res.Stdout+res.Stderr)
		if err != nil || !res.OK() {
			p.DeleteFailed++
			fmt.Fprintf(errOut, "  %s削除に失敗（継続します）%s: %s\n", c.yellow, c.reset, d.Path)
			continue
		}
		p.Deleted++
		fmt.Fprintf(out, "  %s削除%s: %s\n", c.green, c.reset, d.Path)
	}

	prunes := p.PruneRepos()
	if len(prunes) > 0 {
		Section(out, opt.Color, "prune の実行")
	}
	for _, repo := range prunes {
		res, err := r.Run(ctx, execx.Cmd{
			Name: "git", Args: []string{"-C", repo, "worktree", "prune", "-v"},
		})
		WriteIndented(out, res.Stdout+res.Stderr)
		if err != nil || !res.OK() {
			fmt.Fprintf(errOut, "  %sprune に失敗（継続します）%s: %s\n", c.yellow, c.reset, repo)
		}
	}
}
