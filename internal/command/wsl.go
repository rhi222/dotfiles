package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/wsl"
)

const wslUsage = `使い方: dotctl wsl cleanup [--execute]

  WSL2 開発環境のキャッシュを掃除する。既定は dry-run。

  --execute   実際に削除する
  -h, --help  この使い方を表示する

  .cargo / .rustup / ~/go / mise / nvim / claude など開発環境の本体は触らない。
`

func runWSL(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 || args[0] != "cleanup" {
		fmt.Fprint(env.Stderr, wslUsage)
		return 2
	}

	execute := false
	for _, a := range args[1:] {
		switch a {
		case "--execute":
			execute = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, wslUsage)
			return 0
		default:
			fmt.Fprintf(env.Stderr, "Unknown option: %s\n", a)
			fmt.Fprint(env.Stderr, wslUsage)
			return 1
		}
	}

	return wsl.Run(ctx, env.Runner, wsl.Config{
		Home:    env.HomeDir,
		Execute: execute,
		Color:   env.Color,
	}, wsl.IO{Stdout: env.Stdout, Stderr: env.Stderr})
}
