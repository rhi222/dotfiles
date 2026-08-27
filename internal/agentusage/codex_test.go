package agentusage

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// rateLimitsResult は app-server の account/rateLimits/read の result 部。
// 実レスポンスと同じ camelCase・入れ子にする。
func rateLimitsResult(primary, secondary string) string {
	return `{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","primary":` +
		primary + `,"secondary":` + secondary + `,"planType":"team"},` +
		`"rateLimitsByLimitId":{"codex":{"primary":` + primary + `}}}}`
}

func codexWindowJSON(usedPercent, windowMins, resetsAt string) string {
	return `{"usedPercent":` + usedPercent + `,"windowDurationMins":` + windowMins +
		`,"resetsAt":` + resetsAt + `}`
}

// fakeCodex は `codex app-server` の stdio JSON-RPC を模した実行ファイルを作る。
// initialize を受け取る前に rateLimits へ答えないので、送信順もここで検証される。
func fakeCodex(t *testing.T, responseLine string) string {
	t.Helper()
	dir := t.TempDir()
	respFile := filepath.Join(dir, "response.json")
	if err := os.WriteFile(respFile, []byte(responseLine+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	script := `#!/bin/sh
init=0
while IFS= read -r line; do
  case "$line" in
    *'"initialize"'*) init=1; echo '{"jsonrpc":"2.0","id":1,"result":{}}' ;;
    *'account/rateLimits/read'*)
      if [ "$init" -eq 0 ]; then
        echo '{"jsonrpc":"2.0","id":2,"error":{"code":-32002,"message":"not initialized"}}'
        exit 0
      fi
      cat "` + respFile + `"
      exit 0 ;;
  esac
done
`
	return writeExecutable(t, dir, script)
}

func writeExecutable(t *testing.T, dir, script string) string {
	t.Helper()
	path := filepath.Join(dir, "codex")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFetchCodex(t *testing.T) {
	bin := fakeCodex(t, rateLimitsResult(codexWindowJSON("4", "10080", "1788143696"), "null"))
	s, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Unix(1787900000, 0))
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly == nil || s.Weekly.Percent != 4 {
		t.Errorf("Weekly = %+v, want percent 4", s.Weekly)
	}
	if s.Weekly.ResetsAt != 1788143696 {
		t.Errorf("ResetsAt = %d", s.Weekly.ResetsAt)
	}
	if s.FetchedAt != 1787900000 {
		t.Errorf("FetchedAt = %d", s.FetchedAt)
	}
	if s.Session != nil {
		t.Errorf("weekly 窓しか無いのに Session が入っている: %+v", s.Session)
	}
	if s.Fable != nil {
		t.Errorf("Codex に Fable は無いはず: %+v", s.Fable)
	}
}

func TestFetchCodexHomeSetsEnvironment(t *testing.T) {
	dir := t.TempDir()
	logFile := filepath.Join(dir, "codex-home.log")
	home := filepath.Join(dir, "override home")
	t.Setenv("CODEX_HOME", filepath.Join(dir, "inherited home"))
	bin := writeExecutable(t, dir, `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      printf '%s' "$CODEX_HOME" >"`+logFile+`"
      echo '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":8,"windowDurationMins":10080,"resetsAt":99}}}}'
      exit 0 ;;
  esac
done
`)
	if _, err := FetchCodexHome(context.Background(), bin, home, 10*time.Second, time.Now()); err != nil {
		t.Fatalf("FetchCodexHome: %v", err)
	}
	got, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != home {
		t.Errorf("CODEX_HOME = %q, want %q", got, home)
	}
}

func TestFetchCodexSecondaryWeekly(t *testing.T) {
	// 実アカウントの形: primary が 5h 窓（300分）・secondary が weekly（10080分）
	bin := fakeCodex(t, rateLimitsResult(
		codexWindowJSON("80", "300", "1787910000"),
		codexWindowJSON("33.4", "10080", "1787957065"),
	))
	s, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 33 { // 33.4 → 四捨五入で 33
		t.Errorf("Weekly.Percent = %d, want 33", s.Weekly.Percent)
	}
	if s.Weekly.ResetsAt != 1787957065 {
		t.Errorf("ResetsAt = %d, want secondary の値", s.Weekly.ResetsAt)
	}
	if s.Session == nil {
		t.Fatal("5h 窓が取れていない")
	}
	if s.Session.Percent != 80 {
		t.Errorf("Session.Percent = %d, want 80", s.Session.Percent)
	}
	if s.Session.ResetsAt != 1787910000 {
		t.Errorf("Session.ResetsAt = %d, want primary の値", s.Session.ResetsAt)
	}
}

func TestFetchCodexSessionInSecondary(t *testing.T) {
	// 並び順に依存しない。weekly が primary、5h が secondary でも同じ結果にする
	bin := fakeCodex(t, rateLimitsResult(
		codexWindowJSON("33", "10080", "1787957065"),
		codexWindowJSON("80", "300", "1787910000"),
	))
	s, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 33 || s.Weekly.ResetsAt != 1787957065 {
		t.Errorf("Weekly = %+v, want 33%% / 1787957065", s.Weekly)
	}
	if s.Session == nil || s.Session.Percent != 80 || s.Session.ResetsAt != 1787910000 {
		t.Errorf("Session = %+v, want 80%% / 1787910000", s.Session)
	}
}

func TestFetchCodexJSONRPCError(t *testing.T) {
	// 未ログインなどで error が返るときは err にして旧値温存へ倒す
	dir := t.TempDir()
	bin := writeExecutable(t, dir, `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      echo '{"jsonrpc":"2.0","id":2,"error":{"code":401,"message":"not logged in"}}'
      exit 0 ;;
  esac
done
`)
	_, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now())
	if err == nil {
		t.Fatal("JSON-RPC error で err が nil")
	}
	if !strings.Contains(err.Error(), "not logged in") {
		t.Errorf("err = %v, message を含めてほしい", err)
	}
}

func TestFetchCodexNoRateLimits(t *testing.T) {
	bin := fakeCodex(t, `{"jsonrpc":"2.0","id":2,"result":{}}`)
	if _, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now()); err == nil {
		t.Error("rateLimits が無いのに err が nil")
	}
}

func TestFetchCodexIgnoresOtherMessages(t *testing.T) {
	// app-server は通知やサーバ→クライアント要求を混ぜてくる。id=2 だけを拾う
	dir := t.TempDir()
	bin := writeExecutable(t, dir, `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      echo '{"jsonrpc":"2.0","method":"sessionConfigured","params":{}}'
      echo '{"jsonrpc":"2.0","id":"srv-1","method":"applyPatchApproval","params":{}}'
      echo '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":42}}}}'
      exit 0 ;;
  esac
done
`)
	s, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 7 {
		t.Errorf("Weekly.Percent = %d, want 7", s.Weekly.Percent)
	}
}

func TestFetchCodexMissingBinary(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "no-such-codex")
	if _, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now()); err == nil {
		t.Error("codex が無いのに err が nil")
	}
}

func TestFetchCodexTimeout(t *testing.T) {
	// 応答しない app-server で固まらず、timeout で err に倒れる
	bin := writeExecutable(t, t.TempDir(), "#!/bin/sh\nsleep 30\n")
	start := time.Now()
	if _, err := FetchCodex(context.Background(), bin, 300*time.Millisecond, time.Now()); err == nil {
		t.Error("応答なしで err が nil")
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Errorf("timeout が効いていない: %v", elapsed)
	}
}

// 実 app-server は stdin が閉じると応答前に終了する。
// 送信後に閉じてしまうと「応答しなかった」で毎回失敗するので、
// 応答を読み終えるまで stdin を開けておく。
func TestFetchCodexKeepsStdinOpenUntilResponse(t *testing.T) {
	bin := writeExecutable(t, t.TempDir(), `#!/bin/bash
while IFS= read -r line; do
  case "$line" in
    *'account/rateLimits/read'*)
      # stdin が閉じていれば即 EOF（rc=1）、開いていれば timeout（rc>128）
      read -t 0.5 -r _extra
      [ "$?" -eq 1 ] && exit 0
      echo '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"primary":{"usedPercent":11,"windowDurationMins":10080,"resetsAt":99}}}}'
      exit 0 ;;
  esac
done
`)
	s, err := FetchCodex(context.Background(), bin, 10*time.Second, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 11 {
		t.Errorf("Weekly.Percent = %d, want 11", s.Weekly.Percent)
	}
}
