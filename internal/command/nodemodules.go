package command

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/rhi222/dotfiles/internal/nodemodules"
)

const nodeModulesUsage = `使い方: dotctl node-modules cleanup [--execute] [--days N]

  使っていない repository の node_modules を洗い出す。既定は dry-run。
  HEAD の commit と install の両方が N 日（既定 90）より古いものを候補にする。

  --execute   実際に削除する（pnpm の場合は pnpm store prune も実行する）
  --days N    古いとみなす日数
  -h, --help  この使い方を表示する

  git 管理外の node_modules は判定できないので消さない。
`

func runNodeModules(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 || args[0] != "cleanup" {
		fmt.Fprint(env.Stderr, nodeModulesUsage)
		return 2
	}

	cfg := nodemodules.Config{
		Roots: strings.Fields(env.NodeModulesRoots),
		Days:  90,
		Now:   time.Now(),
	}
	rest := args[1:]
	for i := 0; i < len(rest); i++ {
		switch a := rest[i]; a {
		case "--execute":
			cfg.Execute = true
		case "--days":
			n := -1
			if i+1 < len(rest) {
				n, _ = strconv.Atoi(rest[i+1])
				i++
			}
			if n <= 0 {
				fmt.Fprintf(env.Stderr, "--days には正の整数を指定してください\n%s", nodeModulesUsage)
				return 1
			}
			cfg.Days = n
		case "-h", "--help":
			fmt.Fprint(env.Stdout, nodeModulesUsage)
			return 0
		default:
			fmt.Fprintf(env.Stderr, "Unknown option: %s\n%s", a, nodeModulesUsage)
			return 1
		}
	}

	return nodemodules.Run(ctx, env.Runner, cfg, nodemodules.IO{Stdout: env.Stdout, Stderr: env.Stderr})
}
