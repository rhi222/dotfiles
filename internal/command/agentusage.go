package command

import (
	"context"
	"fmt"
	"os/exec"
	"syscall"
	"time"

	"github.com/rhi222/dotfiles/internal/agentusage"
)

const agentUsageUsage = `使い方: dotctl agent-usage <line|detail|refresh>

  AI agent（Claude Code / Codex）のレート上限を表示する。

  line     herdr tab bar 用の1行（キャッシュが古ければ裏で refresh を起動）
  detail [--color]  popup 用の詳細表示（--color で ANSI 色付き）
  refresh  いま取得してキャッシュを更新する
`

func runAgentUsage(ctx context.Context, args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, agentUsageUsage)
		return 2
	}
	cfg := env.AgentUsage
	switch args[0] {
	case "line":
		// **常に exit 0・1行（改行なし）。** herdr の tab bar が呼ぶので、
		// 失敗で非0を返すと欄が前回値のまま固まる。読めなければ空を出して落とす。
		c, err := agentusage.LoadCache(cfg.CacheFile)
		if err != nil || cacheAge(c, cfg) > cfg.TTL {
			spawnRefresh(env)
		}
		if err == nil {
			fmt.Fprint(env.Stdout, agentusage.RenderLine(c, cfg.NowOrDefault(), cfg.StaleAfter))
		}
		return 0
	case "detail":
		c, _ := agentusage.LoadCache(cfg.CacheFile) // 無ければ空 Cache → 案内が出る
		if len(args) > 1 && args[1] == "--color" {
			fmt.Fprintln(env.Stdout, agentusage.RenderDetailColor(c, cfg.NowOrDefault(), cfg.StaleAfter))
		} else {
			fmt.Fprintln(env.Stdout, agentusage.RenderDetail(c, cfg.NowOrDefault(), cfg.StaleAfter))
		}
		return 0
	case "refresh":
		if err := agentusage.Refresh(ctx, cfg); err != nil {
			fmt.Fprintf(env.Stderr, "agent-usage refresh: %v\n", err)
			return 1
		}
		return 0
	case "-h", "--help":
		fmt.Fprint(env.Stdout, agentUsageUsage)
		return 0
	default:
		fmt.Fprintf(env.Stderr, "agent-usage: 知らない操作: %s\n\n%s", args[0], agentUsageUsage)
		return 2
	}
}

// cacheAge は新しい方の fetched_at からの経過。両側とも無ければ「無限に古い」。
func cacheAge(c agentusage.Cache, cfg agentusage.Config) time.Duration {
	var latest int64
	if c.Claude != nil && c.Claude.FetchedAt > latest {
		latest = c.Claude.FetchedAt
	}
	if c.Codex != nil && c.Codex.FetchedAt > latest {
		latest = c.Codex.FetchedAt
	}
	if latest == 0 {
		return time.Duration(1<<62 - 1)
	}
	return cfg.NowOrDefault().Sub(time.Unix(latest, 0))
}

// spawnRefresh は自分自身を refresh で detached 起動する。
//
// tab bar の timeout は 2秒なので、ネットワークを line の中で待てない。
// 起動失敗は握りつぶす（次の呼び出しでまた試みる）。ロックは持たない —
// 呼び出し間隔が 60秒で HTTP timeout が 10秒なので、多重起動しても
// 原子書き込みが壊れることはなく、プロセス数も高々1〜2で済む。
func spawnRefresh(env Env) {
	if env.AgentUsageNoSpawn || env.AgentUsageSelfExe == "" {
		return
	}
	cmd := exec.Command(env.AgentUsageSelfExe, "agent-usage", "refresh")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	_ = cmd.Start()
	if cmd.Process != nil {
		_ = cmd.Process.Release()
	}
}
