package command

import (
	"context"
	"fmt"

	"github.com/rhi222/dotfiles/internal/docker"
)

const dockerUsage = `使い方: dotctl docker <subcommand>

  clean [-a] [--status]   不要リソースを掃除する（既定は軽掃除。-a で重掃除）
  refresh                 キャッシュ更新のみ（起動時通知が background で使う）
  notice                  起動時通知を出す。キャッシュが TTL 超なら 0
  stale                   キャッシュが TTL 超なら 0

  named volume は軽・重どちらでも削除しない。消すときは docker volume rm を使う。
  稼働中コンテナも停止しない。一覧を見て手動で判断する。
`

func runDocker(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, dockerUsage)
		return 2
	}
	cfg := env.Docker

	switch args[0] {
	case "notice":
		// **通知と stale 判定を1プロセスにまとめる。** 別々に呼ぶと、dotctl の
		// version skew 警告が fish 起動時に同じ文言で2回出る。
		// キャッシュを読むだけで、遅い更新は終了コードを見た shell が background
		// に逃がす。
		s, ok := docker.ReadStats(cfg.CacheFile)
		if ok {
			if line := docker.Notice(s, cfg, docker.DirExists); line != "" {
				fmt.Fprintln(env.Stdout, line)
			}
		}
		if docker.IsStale(cfg) {
			return 0
		}
		return 1

	case "stale":
		if docker.IsStale(cfg) {
			return 0
		}
		return 1

	case "refresh":
		if err := docker.UpdateStats(ctx, env.Runner, cfg); err != nil {
			fmt.Fprintf(env.Stderr, "%v\n", err)
			return 1
		}
		return 0

	case "clean":
		return runDockerClean(ctx, args[1:], env)

	case "-h", "--help":
		fmt.Fprint(env.Stdout, dockerUsage)
		return 0

	default:
		fmt.Fprintf(env.Stderr, "dotctl docker: 知らないサブコマンド: %s\n\n%s", args[0], dockerUsage)
		return 2
	}
}

func runDockerClean(ctx context.Context, args []string, env Env) int {
	mode := docker.Light
	statusOnly := false

	for _, a := range args {
		switch a {
		case "-a", "--all":
			mode = docker.Heavy
		case "--status":
			statusOnly = true
		case "-h", "--help":
			fmt.Fprint(env.Stdout, dockerUsage)
			return 0
		default:
			fmt.Fprintf(env.Stderr, "dclean: 不明な引数: %s\n", a)
			fmt.Fprint(env.Stderr, dockerUsage)
			return 2
		}
	}

	cfg := env.Docker
	w := docker.IO{Stdout: env.Stdout, Stderr: env.Stderr, Confirm: env.ConfirmFunc}

	// **プレビューは削除直前の実データで出す。** 手動実行なので 5 秒待って構わない。
	if err := docker.UpdateStats(ctx, env.Runner, cfg); err != nil {
		fmt.Fprintf(env.Stderr, "%v\n", err)
		return 1
	}
	s, ok := docker.ReadStats(cfg.CacheFile)
	if !ok {
		fmt.Fprintln(env.Stderr, "キャッシュを読めませんでした")
		return 1
	}

	docker.Preview(ctx, env.Runner, cfg, s, mode, w, docker.DirExists)
	if statusOnly {
		return 0
	}

	if !confirm(w, "実行しますか? [y/N] ") {
		fmt.Fprintln(env.Stdout, "中止しました")
		return 0
	}

	rc := docker.Run(ctx, env.Runner, mode, w)
	// 実行後にキャッシュを作り直す（次回の起動時通知を最新にする）
	_ = docker.UpdateStats(ctx, env.Runner, cfg)
	return rc
}

func confirm(w docker.IO, prompt string) bool {
	if w.Confirm != nil {
		return w.Confirm(prompt)
	}
	return confirmTTY(prompt, w.Stdout)
}
