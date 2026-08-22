package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/privatebundle"
)

const privateUsage = `使い方: dotctl private-bundle <subcommand>

  adopt [--execute]        散らばった実体を集約先へ（旧環境で1回）
  export [--out PATH]      パスワード付き zip に固める
  import <zip> [--force]   zip を集約先へ展開する
  status                   宣言を基準に状態を報告する
`

func runPrivateBundle(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, privateUsage)
		return 2
	}
	cfg := env.Private
	w := privatebundle.IO{Stdout: env.Stdout, Stderr: env.Stderr}

	switch args[0] {
	case "adopt":
		execute := false
		for _, a := range args[1:] {
			if a == "--execute" {
				execute = true
			} else {
				fmt.Fprintf(env.Stderr, "[FAIL] 不明な引数: %s\n", a)
				return 2
			}
		}
		return privatebundle.Adopt(ctx, env.Runner, cfg, execute, w)

	case "export":
		out := ""
		rest := args[1:]
		for i := 0; i < len(rest); i++ {
			if rest[i] == "--out" {
				if i+1 >= len(rest) {
					fmt.Fprintln(env.Stderr, "[FAIL] --out にパスが必要です")
					return 2
				}
				out = rest[i+1]
				i++
				continue
			}
			fmt.Fprintf(env.Stderr, "[FAIL] 不明な引数: %s\n", rest[i])
			return 2
		}
		return privatebundle.Export(ctx, env.Runner, cfg, out, w)

	case "import":
		// **引数なしは「zip がありません」で 1。** Shell 版の終了コードに
		// 合わせている（usage の 2 ではない）
		zipfile := ""
		var opts []string
		if len(args) >= 2 {
			zipfile = args[1]
			opts = args[2:]
		}
		force := false
		for _, a := range opts {
			if a == "--force" {
				force = true
			} else {
				fmt.Fprintf(env.Stderr, "[FAIL] 不明な引数: %s\n", a)
				return 2
			}
		}
		return privatebundle.Import(ctx, env.Runner, cfg, zipfile, force, w)

	case "status":
		return privatebundle.Status(ctx, env.Runner, cfg, w)

	case "-h", "--help":
		fmt.Fprint(env.Stdout, privateUsage)
		return 0

	default:
		fmt.Fprint(env.Stderr, privateUsage)
		return 2
	}
}
