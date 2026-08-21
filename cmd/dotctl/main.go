// Command dotctl は dotfiles の運用コマンドをまとめた CLI。
//
// **入口は薄く保つ。** 分岐とロジックは internal/command 側にあり、
// ここは os の面（引数・標準出力・終了コード・環境変数・TTY 判定）を
// 渡すだけにする。そうすることで dispatcher 全体をテストから駆動できる。
package main

import (
	"context"
	"os"

	"github.com/rhi222/dotfiles/internal/buildinfo"
	"github.com/rhi222/dotfiles/internal/command"
	"github.com/rhi222/dotfiles/internal/execx"
)

// defaultWorktreeRoots は worktree の走査ルート（Shell 版と同じ既定）。
const defaultWorktreeRoots = "/data/git-repos"

func main() {
	os.Exit(command.Run(context.Background(), os.Args[1:], command.Env{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Runner: execx.New(),
		Commit: buildinfo.Commit,
		Repo:   buildinfo.Repo,

		WorktreeRoots:      envOr("WORKTREE_CLEANUP_ROOTS", defaultWorktreeRoots),
		WorktreePRStateCmd: os.Getenv("WORKTREE_CLEANUP_PR_STATE_CMD"),

		Color: isTerminal(os.Stdout),
	}))
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// isTerminal は f が端末かどうか。**着色の判定はここだけで行う。**
// internal 側は Color フラグしか見ないので、テストで色を制御できる。
func isTerminal(f *os.File) bool {
	st, err := f.Stat()
	if err != nil {
		return false
	}
	return st.Mode()&os.ModeCharDevice != 0
}
