package command

import (
	"bytes"
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rhi222/dotfiles/internal/agentusage"
)

func agentUsageEnv(t *testing.T, cacheFile string) (Env, *bytes.Buffer) {
	t.Helper()
	var out bytes.Buffer
	env := Env{
		Stdout: &out,
		Stderr: &bytes.Buffer{},
		AgentUsage: agentusage.Config{
			CacheFile:  cacheFile,
			TTL:        5 * time.Minute,
			StaleAfter: 15 * time.Minute,
			Now:        func() time.Time { return time.Unix(1787900000, 0) },
		},
		AgentUsageNoSpawn: true, // テストから外部プロセスを起動しない
	}
	return env, &out
}

func writeUsageCache(t *testing.T, path string, fetchedAt int64) {
	t.Helper()
	now := int64(1787900000)
	c := agentusage.Cache{
		Claude: &agentusage.Side{
			FetchedAt: fetchedAt,
			Session:   &agentusage.Window{Percent: 45, ResetsAt: now + 10020}, // 2h47m
			Weekly:    &agentusage.Window{Percent: 50, ResetsAt: now + 3*86400 + 11*3600},
			Fable:     &agentusage.Window{Percent: 29, ResetsAt: now + 3*86400 + 11*3600},
		},
	}
	if err := agentusage.WriteCache(path, c); err != nil {
		t.Fatal(err)
	}
}

func TestAgentUsageLine(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "usage.json")
	writeUsageCache(t, cache, 1787900000-60)
	env, out := agentUsageEnv(t, cache)
	if code := Run(context.Background(), []string{"agent-usage", "line"}, env); code != 0 {
		t.Fatalf("exit = %d", code)
	}
	got := out.String()
	if got != "CC 45% (2h47m) W 50% F 29% (3d11h)" {
		t.Errorf("line = %q", got)
	}
	if strings.Contains(got, "\n") {
		t.Error("line 出力に改行が含まれる")
	}
}

func TestAgentUsageLineNoCache(t *testing.T) {
	env, out := agentUsageEnv(t, filepath.Join(t.TempDir(), "none.json"))
	if code := Run(context.Background(), []string{"agent-usage", "line"}, env); code != 0 {
		t.Fatalf("exit = %d（キャッシュ無しでも 0 のこと）", code)
	}
	if out.String() != "" {
		t.Errorf("キャッシュ無しで出力がある: %q", out.String())
	}
}

func TestAgentUsageDetail(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "usage.json")
	writeUsageCache(t, cache, 1787900000-60)
	env, out := agentUsageEnv(t, cache)
	if code := Run(context.Background(), []string{"agent-usage", "detail"}, env); code != 0 {
		t.Fatalf("exit = %d", code)
	}
	if !strings.Contains(out.String(), "Claude Code") {
		t.Errorf("detail = %q", out.String())
	}
	if strings.Contains(out.String(), "\x1b[") {
		t.Errorf("detail に意図しない ANSI escape がある: %q", out.String())
	}

	env, out = agentUsageEnv(t, cache)
	if code := Run(context.Background(), []string{"agent-usage", "detail", "--color"}, env); code != 0 {
		t.Fatalf("detail --color exit = %d", code)
	}
	if !strings.Contains(out.String(), "\x1b[") {
		t.Errorf("detail --color に ANSI escape が無い: %q", out.String())
	}
}

func TestAgentUsageUnknown(t *testing.T) {
	env, _ := agentUsageEnv(t, filepath.Join(t.TempDir(), "u.json"))
	if code := Run(context.Background(), []string{"agent-usage", "bogus"}, env); code != 2 {
		t.Errorf("exit = %d, want 2", code)
	}
}
