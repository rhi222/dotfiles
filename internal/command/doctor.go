package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/doctor"
)

const doctorUsage = `使い方: dotctl doctor <subcommand>

  residue              宣言のどこにも属さない環境の残骸を洗い出す
  migration [<dir>...] 移行前チェック（リポジトリに残るローカル専用の作業状態）

  residue は見つかっても 0 で返す（情報提供）。
  migration は作業状態が残っていれば 1 で返す。
`

func runDoctor(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, doctorUsage)
		return 2
	}
	w := doctor.IO{Stdout: env.Stdout, Stderr: env.Stderr}

	switch args[0] {
	case "residue":
		found, notes := doctor.CheckResidue(ctx, env.Runner, env.Residue)
		return doctor.RenderResidue(env.Stdout, found, notes)
	case "migration":
		return doctor.CheckMigration(ctx, env.Runner, env.HomeDir, args[1:], w)
	case "-h", "--help":
		fmt.Fprint(env.Stdout, doctorUsage)
		return 0
	default:
		fmt.Fprintf(env.Stderr, "dotctl doctor: 知らないサブコマンド: %s\n\n%s", args[0], doctorUsage)
		return 2
	}
}
