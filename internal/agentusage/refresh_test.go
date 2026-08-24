package agentusage

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func refreshConfig(t *testing.T, endpoint string) Config {
	t.Helper()
	dir := t.TempDir()
	return Config{
		CacheFile:       filepath.Join(dir, "cache", "usage.json"),
		CredentialsFile: writeCredentials(t, "tok"),
		CodexBin:        fakeCodex(t, rateLimitsResult(codexWindowJSON("2", "10080", "1787957065"), "null")),
		Endpoint:        endpoint,
		TTL:             5 * time.Minute,
		StaleAfter:      15 * time.Minute,
		HTTPTimeout:     2 * time.Second,
		CodexTimeout:    10 * time.Second,
		Now:             func() time.Time { return time.Unix(1787900000, 0) },
	}
}

func TestRefreshBothSides(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	warns, err := Refresh(context.Background(), cfg)
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if len(warns) != 0 {
		t.Errorf("両側成功なのに警告が出た: %v", warns)
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
	warns, err := Refresh(context.Background(), cfg)
	if err != nil {
		t.Fatalf("Refresh（片側成功）: %v", err)
	}
	c, _ := LoadCache(cfg.CacheFile)
	if c.Claude == nil || c.Claude.Session.Percent != 99 || c.Claude.FetchedAt != 42 {
		t.Errorf("Claude の旧値が温存されていない: %+v", c.Claude)
	}
	if c.Codex == nil || c.Codex.Weekly.Percent != 2 {
		t.Errorf("Codex が更新されていない: %+v", c.Codex)
	}
	// 片側失敗を握りつぶすと、データ源が消えても表示が黙って欠けるだけになる
	if len(warns) != 1 {
		t.Fatalf("警告が %d 件、1件を期待: %v", len(warns), warns)
	}
	if !strings.Contains(warns[0].Error(), "claude") {
		t.Errorf("警告にどちらの側か入っていない: %v", warns[0])
	}
}

func TestRefreshWarnsWhenCodexFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	cfg.CodexBin = filepath.Join(t.TempDir(), "no-such-codex")
	warns, err := Refresh(context.Background(), cfg)
	if err != nil {
		t.Fatalf("Refresh（Claude だけ成功）: %v", err)
	}
	if len(warns) != 1 || !strings.Contains(warns[0].Error(), "codex") {
		t.Fatalf("codex の失敗が警告に出ていない: %v", warns)
	}
}

func TestRefreshBothFail(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	cfg.CodexBin = filepath.Join(t.TempDir(), "no-such-codex")
	if _, err := Refresh(context.Background(), cfg); err == nil {
		t.Error("両側失敗で err が nil")
	}
}
