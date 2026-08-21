// Command dotctl は dotfiles の運用コマンドをまとめた CLI。
//
// **入口は薄く保つ。** 分岐とロジックは internal/command 側にあり、
// ここは os の面（引数・標準出力・終了コード）を渡すだけにする。
// そうすることで dispatcher 全体をテストから駆動できる。
package main

import (
	"context"
	"os"

	"github.com/rhi222/dotfiles/internal/buildinfo"
	"github.com/rhi222/dotfiles/internal/command"
	"github.com/rhi222/dotfiles/internal/execx"
)

func main() {
	os.Exit(command.Run(context.Background(), os.Args[1:], command.Env{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Runner: execx.New(),
		Commit: buildinfo.Commit,
		Repo:   buildinfo.Repo,
	}))
}
