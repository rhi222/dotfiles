package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/worktree"
)

const worktreeUsage = `使い方: dotctl worktree <subcommand>

サブコマンド:
  cleanup   消し忘れた git worktree を洗い出して掃除する
`

const cleanupUsage = `使い方: dotctl worktree cleanup [--execute] [--force] [--size]

  (オプションなし)  dry-run。削除候補を一覧表示する
  --execute         実際に削除する
  --force           追跡ファイルに未コミット変更がある worktree も削除する
                    （未追跡ファイルのみの場合は --force なしでも削除対象になり、
                     理由文に「未追跡 N 件あり」と件数を併記する）
  --size            DELETE 候補のサイズを測って解放見込みを表示する
  -h, --help        この使い方を表示する
`

func runWorktree(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, worktreeUsage)
		return 2
	}
	switch args[0] {
	case "cleanup":
		return runWorktreeCleanup(ctx, args[1:], env)
	default:
		fmt.Fprintf(env.Stderr, "dotctl worktree: 知らないサブコマンド: %s\n\n%s", args[0], worktreeUsage)
		return 2
	}
}

func runWorktreeCleanup(ctx context.Context, args []string, env Env) int {
	cfg := worktree.Config{
		Roots:      env.WorktreeRoots,
		Repos:      env.WorktreeRepos,
		PRStateCmd: env.WorktreePRStateCmd,
	}
	execute := false

	for _, a := range args {
		switch a {
		case "--execute":
			execute = true
		case "--force":
			cfg.Force = true
		case "--size":
			cfg.ShowSize = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, cleanupUsage)
			return 0
		default:
			fmt.Fprintf(env.Stderr, "Unknown option: %s\n%s", a, cleanupUsage)
			return 1
		}
	}

	plan := worktree.BuildPlan(ctx, env.Runner, cfg)
	ropt := worktree.RenderOptions{Execute: execute, ShowSize: cfg.ShowSize, Color: env.Color}

	// **表示は Plan だけを読む。** 実行の前後で同じ Plan を参照するので、
	// 「表示したものと消したものが違う」状態が構造的に起きない。
	//
	// 順序は Shell 版に合わせる: 本文 → 削除/prune の実行ログ → サマリ。
	fmt.Fprint(env.Stdout, worktree.RenderHead(plan, ropt))
	if execute {
		worktree.Execute(ctx, env.Runner, plan, worktree.ExecOptions{
			Stdout: env.Stdout, Stderr: env.Stderr, Color: env.Color,
		})
	}
	fmt.Fprint(env.Stdout, worktree.RenderSummary(plan, ropt))
	return 0
}
