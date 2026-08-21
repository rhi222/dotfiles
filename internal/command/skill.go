package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/skill"
)

const skillUsage = `使い方: dotctl skill <subcommand>

サブコマンド:
  audit [--quiet] <skill-dir>                       skill の内容を機械的に検査する
  vendor add <owner/repo|git-url> <sub-path> [name]  vendored skill を取り込む
  vendor update <name>                               upstream へ追随させる
  vendor status [--no-network]                        取込済みを点検する
  vendor list                                        取込済みを一覧する
  trusted <owner/repo>                               owner が allowlist にあるか（終了コードで返す）
`

const auditUsage = `使い方: dotctl skill audit [--quiet] <skill-dir>

  <skill-dir> 配下の全テキストファイルを走査し、疑わしい箇所を
  [LEVEL] path:line 説明 の形式で列挙する。

  --quiet  findings を出さず要約行だけを出す
`

const vendorUsage = `使い方:
  dotctl skill vendor add <owner/repo|git-url> <sub-path> [name]
  dotctl skill vendor update <name>
  dotctl skill vendor status [--no-network]
  dotctl skill vendor list

  <sub-path> はリポジトリ内の skill ディレクトリ。直下にある場合は "." を渡す。
  [name] を省略すると <sub-path> の basename（"." のときはリポジトリ名）を使う。
`

func runSkill(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, skillUsage)
		return 2
	}
	switch args[0] {
	case "audit":
		return runSkillAudit(ctx, args[1:], env)
	case "vendor":
		return runSkillVendor(ctx, args[1:], env)
	case "trusted":
		return runSkillTrusted(args[1:], env)
	case "-h", "--help":
		fmt.Fprint(env.Stdout, skillUsage)
		return 0
	default:
		fmt.Fprintf(env.Stderr, "dotctl skill: 知らないサブコマンド: %s\n\n%s", args[0], skillUsage)
		return 2
	}
}

func runSkillAudit(ctx context.Context, args []string, env Env) int {
	quiet := false
	dir := ""
	for _, a := range args {
		switch a {
		case "--quiet":
			quiet = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, auditUsage)
			return 0
		default:
			if dir != "" {
				fmt.Fprint(env.Stderr, auditUsage)
				return 2
			}
			dir = a
		}
	}
	if dir == "" {
		fmt.Fprint(env.Stderr, auditUsage)
		return 2
	}

	res, err := skill.Audit(ctx, env.Runner, dir)
	if err != nil {
		fmt.Fprintf(env.Stderr, "Error: %v\n", err)
		return 2
	}
	skill.RenderAudit(env.Stdout, res, quiet)
	return res.ExitCode()
}

func runSkillVendor(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, vendorUsage)
		return 2
	}
	cfg := env.Vendor
	w := skill.VendorIO{Stdout: env.Stdout, Stderr: env.Stderr}

	switch args[0] {
	case "add":
		rest := args[1:]
		if len(rest) < 2 {
			fmt.Fprint(env.Stderr, vendorUsage)
			return 2
		}
		name := ""
		if len(rest) >= 3 {
			name = rest[2]
		}
		return skill.VendorAdd(ctx, env.Runner, cfg, rest[0], rest[1], name, w)
	case "update":
		if len(args) != 2 {
			fmt.Fprint(env.Stderr, vendorUsage)
			return 2
		}
		return skill.VendorUpdate(ctx, env.Runner, cfg, args[1], w)
	case "status":
		noNetwork := false
		for _, a := range args[1:] {
			if a == "--no-network" {
				noNetwork = true
			} else {
				fmt.Fprint(env.Stderr, vendorUsage)
				return 2
			}
		}
		return skill.VendorStatus(ctx, env.Runner, cfg, noNetwork, w)
	case "list":
		return skill.VendorList(cfg, w)
	case "-h", "--help":
		fmt.Fprint(env.Stdout, vendorUsage)
		return 0
	default:
		fmt.Fprint(env.Stderr, vendorUsage)
		return 2
	}
}

// runSkillTrusted は owner が allowlist にあるかを終了コードで返す。
//
// **Shell 側から呼ぶための口。** allowlist の判定は skill-add.sh と
// setup-claude-skills.sh の両方で要るので、Shell の lib と Go で二重に
// 実装しないよう、判定はここ1か所に置いて Shell から呼ばせる。
func runSkillTrusted(args []string, env Env) int {
	if len(args) != 1 {
		fmt.Fprintln(env.Stderr, "使い方: dotctl skill trusted <owner/repo>")
		return 2
	}
	if skill.RequireTrustedOwner(env.TrustedOwnersFile, args[0], env.Stderr) {
		return 0
	}
	return 1
}
