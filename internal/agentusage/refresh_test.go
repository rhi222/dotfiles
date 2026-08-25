package agentusage

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
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

func parallelCodex(t *testing.T, overrideHome string) string {
	t.Helper()
	dir := t.TempDir()
	markerDir := filepath.Join(dir, "markers")
	if err := os.Mkdir(markerDir, 0o755); err != nil {
		t.Fatal(err)
	}
	script := `#!/bin/sh
if [ "$CODEX_HOME" = "` + overrideHome + `" ]; then
  role=override
  other=default
  percent=9
else
  role=default
  other=override
  percent=2
fi
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      : >"` + markerDir + `/"$role
      count=0
      while [ ! -f "` + markerDir + `/"$other ]; do
        count=$((count + 1))
        [ "$count" -gt 200 ] && exit 1
        sleep 0.01
      done
      echo "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":$percent,\"windowDurationMins\":10080,\"resetsAt\":1787957065}}}}"
      exit 0 ;;
  esac
done
`
	return writeExecutable(t, dir, script)
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

func TestRefreshWithoutOverrideStartsOneCodex(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	dir := t.TempDir()
	logFile := filepath.Join(dir, "starts.log")
	cfg.CodexBin = writeExecutable(t, dir, `#!/bin/sh
echo call >>"`+logFile+`"
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      echo '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1787957065}}}}'
      exit 0 ;;
  esac
done
`)
	if _, err := Refresh(context.Background(), cfg); err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	b, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Count(string(b), "call\n"); got != 1 {
		t.Errorf("Codex起動回数 = %d, want 1", got)
	}
}

// default と override を直列にすると、先に起動したfakeが相手のmarkerを待って失敗する。
// 両方がbarrierへ到達できることで、account数を増やしてもtimeoutが加算されないことを固定する。
func TestRefreshCodexAccountsInParallel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	cfg.CodexOverrideHome = filepath.Join(t.TempDir(), "override home")
	cfg.CodexBin = parallelCodex(t, cfg.CodexOverrideHome)
	warns, err := Refresh(context.Background(), cfg)
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if len(warns) != 0 {
		t.Fatalf("警告 = %v", warns)
	}
	c, err := LoadCache(cfg.CacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if c.Codex == nil || c.Codex.Weekly.Percent != 2 {
		t.Errorf("default = %+v", c.Codex)
	}
	if c.CodexOverride == nil || c.CodexOverride.Weekly.Percent != 9 {
		t.Errorf("override = %+v", c.CodexOverride)
	}
}

func TestRefreshKeepsOldOverrideOnFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	cfg.CodexOverrideHome = filepath.Join(t.TempDir(), "override")
	dir := t.TempDir()
	cfg.CodexBin = writeExecutable(t, dir, `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      [ "$CODEX_HOME" = "`+cfg.CodexOverrideHome+`" ] && exit 0
      echo '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1787957065}}}}'
      exit 0 ;;
  esac
done
`)
	old := Cache{CodexOverride: &Side{FetchedAt: 42, Weekly: &Window{Percent: 77, ResetsAt: 100}}}
	if err := WriteCache(cfg.CacheFile, old); err != nil {
		t.Fatal(err)
	}
	warns, err := Refresh(context.Background(), cfg)
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if len(warns) != 1 || !strings.Contains(warns[0].Error(), "codex override") {
		t.Fatalf("override の警告が無い: %v", warns)
	}
	c, err := LoadCache(cfg.CacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if c.CodexOverride == nil || c.CodexOverride.Weekly.Percent != 77 || c.CodexOverride.FetchedAt != 42 {
		t.Errorf("override の旧値が温存されていない: %+v", c.CodexOverride)
	}
	if c.Codex == nil || c.Codex.Weekly.Percent != 2 {
		t.Errorf("default が更新されていない: %+v", c.Codex)
	}
}

func TestRefreshRemovesOverrideWhenDisabled(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()
	cfg := refreshConfig(t, srv.URL)
	old := Cache{CodexOverride: &Side{FetchedAt: 42, Weekly: &Window{Percent: 77, ResetsAt: 100}}}
	if err := WriteCache(cfg.CacheFile, old); err != nil {
		t.Fatal(err)
	}
	if _, err := Refresh(context.Background(), cfg); err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	c, err := LoadCache(cfg.CacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if c.CodexOverride != nil {
		t.Errorf("無効化後もoverride cacheが残っている: %+v", c.CodexOverride)
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
	if strings.Contains(warns[0].Error(), "codex default") {
		t.Fatalf("override未設定なのに従来の警告名が変わった: %v", warns)
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
