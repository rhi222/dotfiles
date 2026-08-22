package command

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

const rebuildUsage = `使い方: dotctl rebuild [--skip-tests]

  ビルド時に埋め込まれたrepositoryの scripts/setup-dotctl.sh を実行する。
  repositoryを移動した場合は DOTCTL_REPO で新しい場所を指定する。
`

func runRebuild(ctx context.Context, args []string, env Env) int {
	skipTests := false
	for _, arg := range args {
		switch arg {
		case "--skip-tests":
			skipTests = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, rebuildUsage)
			return 0
		default:
			fmt.Fprintf(env.Stderr, "dotctl rebuild: 不明な引数: %s\n", arg)
			fmt.Fprint(env.Stderr, rebuildUsage)
			return 2
		}
	}

	repo := strings.TrimSpace(env.Repo)
	if repo == "" {
		fmt.Fprintln(env.Stderr,
			"dotctl rebuild: ビルド元のrepositoryが不明。DOTCTL_REPO=/path/to/dotfiles を指定してください")
		return 1
	}
	if env.Runner == nil {
		fmt.Fprintln(env.Stderr, "dotctl rebuild: command runnerがありません")
		return 1
	}

	script := filepath.Join(repo, "scripts", "setup-dotctl.sh")
	cmdArgs := []string{script}
	if skipTests {
		cmdArgs = append(cmdArgs, "--skip-tests")
	}

	fmt.Fprintf(env.Stdout, "dotctl: %s から再ビルドする\n", repo)
	res, err := env.Runner.Run(ctx, execx.Cmd{Name: "bash", Args: cmdArgs, Dir: repo})
	if res.Stdout != "" {
		fmt.Fprint(env.Stdout, res.Stdout)
	}
	if res.Stderr != "" {
		fmt.Fprint(env.Stderr, res.Stderr)
	}
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl rebuild: %v\n", err)
		return 1
	}
	return res.ExitCode
}
