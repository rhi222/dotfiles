package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/pluginvendor"
)

const pluginUsage = `使い方:
  dotctl plugin vendor status [--no-network]
  dotctl plugin vendor update <name> [name...]
`

func runPlugin(ctx context.Context, args []string, env Env) int {
	if len(args) < 2 || args[0] != "vendor" {
		fmt.Fprint(env.Stderr, pluginUsage)
		return 2
	}
	w := pluginvendor.IO{Stdout: env.Stdout, Stderr: env.Stderr, Confirm: env.ConfirmFunc}
	switch args[1] {
	case "status":
		noNetwork := false
		for _, arg := range args[2:] {
			if arg != "--no-network" {
				fmt.Fprint(env.Stderr, pluginUsage)
				return 2
			}
			noNetwork = true
		}
		return pluginvendor.Status(ctx, env.Runner, env.PluginVendor, noNetwork, w)
	case "update":
		if len(args) < 3 {
			fmt.Fprint(env.Stderr, pluginUsage)
			return 2
		}
		rc := 0
		for _, name := range args[2:] {
			if pluginvendor.Update(ctx, env.Runner, env.PluginVendor, name, w) != 0 {
				rc = 1
			}
		}
		return rc
	case "-h", "--help":
		fmt.Fprint(env.Stdout, pluginUsage)
		return 0
	default:
		fmt.Fprint(env.Stderr, pluginUsage)
		return 2
	}
}
