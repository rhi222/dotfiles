package agentusage

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

func refreshConfig(t *testing.T, endpoint string) Config {
	t.Helper()
	dir := t.TempDir()
	day := filepath.Join(dir, "codex-sessions", "2026", "08", "21")
	writeRollout(t, day, "rollout-a.jsonl", []string{rlLine("2.0", "10080", "1787957065")})
	return Config{
		CacheFile:        filepath.Join(dir, "cache", "usage.json"),
		CredentialsFile:  writeCredentials(t, "tok"),
		CodexSessionsDir: filepath.Join(dir, "codex-sessions"),
		Endpoint:         endpoint,
		TTL:              5 * time.Minute,
		StaleAfter:       15 * time.Minute,
		HTTPTimeout:      2 * time.Second,
		Now:              func() time.Time { return time.Unix(1787900000, 0) },
	}
}

func TestRefreshBothSides(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	if err := Refresh(context.Background(), cfg); err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	c, err := LoadCache(cfg.CacheFile)
	if err != nil {
		t.Fatalf("LoadCache: %v", err)
	}
	if c.Claude == nil || c.Claude.Session.Percent != 45 {
		t.Errorf("Claude = %+v", c.Claude)
	}
	if c.Codex == nil || c.Codex.Weekly.Percent != 2 {
		t.Errorf("Codex = %+v", c.Codex)
	}
}

func TestRefreshKeepsOldSideOnFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized) // Claude 側だけ失敗させる
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	// 旧キャッシュに Claude の値を仕込む
	old := Cache{Claude: &Side{FetchedAt: 42, Session: &Window{Percent: 99, ResetsAt: 100}, Weekly: &Window{Percent: 98, ResetsAt: 200}}}
	if err := WriteCache(cfg.CacheFile, old); err != nil {
		t.Fatal(err)
	}
	if err := Refresh(context.Background(), cfg); err != nil {
		t.Fatalf("Refresh（片側成功）: %v", err)
	}
	c, _ := LoadCache(cfg.CacheFile)
	if c.Claude == nil || c.Claude.Session.Percent != 99 || c.Claude.FetchedAt != 42 {
		t.Errorf("Claude の旧値が温存されていない: %+v", c.Claude)
	}
	if c.Codex == nil || c.Codex.Weekly.Percent != 2 {
		t.Errorf("Codex が更新されていない: %+v", c.Codex)
	}
}

func TestRefreshBothFail(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	cfg.CodexSessionsDir = t.TempDir() // rollout も無くす
	if err := Refresh(context.Background(), cfg); err == nil {
		t.Error("両側失敗で err が nil")
	}
}
