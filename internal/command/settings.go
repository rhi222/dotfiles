package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/settings"
)

const settingsUsage = `使い方: dotctl settings sync <claude|windows> <pull|push|status> [オプション]

  claude    ~/.claude/settings.json とリポジトリ版
  windows   .wslconfig と Windows Terminal の settings.json

  pull [--dry-run]  実ファイルをリポジトリに取り込む（通常はこちら）
  push [--force]    リポジトリの内容を実ファイルに書き出す
  status            差分の有無を表示するだけ
`

const windowsSyncUsage = `使い方: dotctl settings sync windows <pull|push|status> [target] [オプション]

  target: wslconfig | terminal（省略時は全部）

  pull [--dry-run]  実ファイルをリポジトリに取り込む（通常はこちら）
  push [--force]    リポジトリの内容を実ファイルに書き出す
  status            差分の有無を表示するだけ
`

func runSettings(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 || args[0] != "sync" {
		fmt.Fprint(env.Stderr, settingsUsage)
		return 2
	}
	rest := args[1:]
	if len(rest) == 0 {
		fmt.Fprint(env.Stderr, settingsUsage)
		return 2
	}

	switch rest[0] {
	case "claude":
		return runSettingsClaude(ctx, rest[1:], env)
	case "windows":
		return runSettingsWindows(ctx, rest[1:], env)
	case "-h", "--help":
		fmt.Fprint(env.Stdout, settingsUsage)
		return 0
	default:
		fmt.Fprintf(env.Stderr, "dotctl settings sync: 知らない対象: %s\n\n%s", rest[0], settingsUsage)
		return 2
	}
}

// parseSyncFlags は pull/push/status に共通のオプションを読む。
func parseSyncFlags(args []string, usage string, env Env) (dryRun, force bool, target string, code int, done bool) {
	for _, a := range args {
		switch a {
		case "--dry-run":
			dryRun = true
		case "--force":
			force = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, usage)
			return false, false, "", 0, true
		default:
			if len(a) > 0 && a[0] == '-' {
				fmt.Fprintf(env.Stderr, "ERROR: 不明なオプション: %s\n%s", a, usage)
				return false, false, "", 1, true
			}
			target = a
		}
	}
	return dryRun, force, target, 0, false
}

func runSettingsClaude(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, settingsUsage)
		return 2
	}
	action := args[0]
	dryRun, force, _, code, done := parseSyncFlags(args[1:], settingsUsage, env)
	if done {
		return code
	}

	cfg := env.ClaudeSettings
	w := settings.IO{Stdout: env.Stdout, Stderr: env.Stderr}

	switch action {
	case "pull":
		return settings.ClaudePull(ctx, env.Runner, cfg, dryRun, w).ExitCode()
	case "push":
		return settings.ClaudePush(ctx, env.Runner, cfg, force, w).ExitCode()
	case "status":
		return settings.ClaudeStatus(ctx, env.Runner, cfg, w).ExitCode()
	default:
		fmt.Fprint(env.Stderr, settingsUsage)
		return 2
	}
}

func runSettingsWindows(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, windowsSyncUsage)
		return 2
	}
	action := args[0]
	dryRun, force, target, code, done := parseSyncFlags(args[1:], windowsSyncUsage, env)
	if done {
		return code
	}

	all := settings.WindowsTargets(env.WindowsSettings)
	selected := all
	if target != "" {
		selected = nil
		for _, t := range all {
			if t.Name == target {
				selected = append(selected, t)
			}
		}
		if selected == nil {
			names := ""
			for i, t := range all {
				if i > 0 {
					names += " "
				}
				names += t.Name
			}
			fmt.Fprintf(env.Stderr, "ERROR: 不明な target: %s（指定できるのは %s）\n", target, names)
			return 1
		}
	}

	w := settings.IO{Stdout: env.Stdout, Stderr: env.Stderr}
	rc := 0
	// **1つの対象の失敗で残りを止めない。** wslconfig が読めない端末でも
	// terminal の同期はできる（Shell 版と同じ倒し方）。
	for _, t := range selected {
		var got settings.Outcome
		switch action {
		case "pull":
			got = settings.WindowsPull(ctx, env.Runner, t, dryRun, w)
		case "push":
			got = settings.WindowsPush(ctx, env.Runner, t, force, w)
		case "status":
			got = settings.WindowsStatus(ctx, env.Runner, t, w)
		default:
			fmt.Fprint(env.Stderr, windowsSyncUsage)
			return 2
		}
		if got.ExitCode() != 0 {
			rc = 1
		}
	}
	return rc
}
