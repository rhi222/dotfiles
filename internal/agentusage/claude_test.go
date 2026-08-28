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

// 実レスポンスの構造を最小化したフィクスチャ（値は架空）
const claudeUsageJSON = `{
  "limits": [
    {"kind": "session", "group": "session", "percent": 45,
     "resets_at": "2026-08-22T04:00:00.014654+00:00", "scope": null},
    {"kind": "weekly_all", "group": "weekly", "percent": 50,
     "resets_at": "2026-08-25T12:00:00.014680+00:00", "scope": null},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 29,
     "resets_at": "2026-08-25T12:00:00.014680+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}}}
  ]
}`

func writeCredentials(t *testing.T, token string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), ".credentials.json")
	body := `{"claudeAiOauth":{"accessToken":"` + token + `"}}`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFetchClaude(t *testing.T) {
	var gotAuth, gotBeta string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotBeta = r.Header.Get("anthropic-beta")
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()

	now := time.Date(2026, 8, 22, 1, 0, 0, 0, time.UTC)
	s, err := FetchClaude(context.Background(), writeCredentials(t, "tok-123"), srv.URL, srv.Client(), now)
	if err != nil {
		t.Fatalf("FetchClaude: %v", err)
	}
	if gotAuth != "Bearer tok-123" {
		t.Errorf("Authorization = %q", gotAuth)
	}
	if gotBeta != "oauth-2025-04-20" {
		t.Errorf("anthropic-beta = %q", gotBeta)
	}
	if s.FetchedAt != now.Unix() {
		t.Errorf("FetchedAt = %d", s.FetchedAt)
	}
	if s.Session == nil || s.Session.Percent != 45 {
		t.Errorf("Session = %+v", s.Session)
	}
	// resets_at "2026-08-22T04:00:00.014654+00:00" → epoch
	if want := time.Date(2026, 8, 22, 4, 0, 0, 14654000, time.UTC).Unix(); s.Session.ResetsAt != want {
		t.Errorf("Session.ResetsAt = %d, want %d", s.Session.ResetsAt, want)
	}
	if s.Weekly == nil || s.Weekly.Percent != 50 {
		t.Errorf("Weekly = %+v", s.Weekly)
	}
	if s.Fable == nil || s.Fable.Percent != 29 {
		t.Errorf("Fable = %+v", s.Fable)
	}
}

func TestFetchClaudeNoScopedLimit(t *testing.T) {
	// weekly_scoped が無いアカウント → Fable は nil、エラーにしない
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"limits":[
			{"kind":"session","percent":10,"resets_at":"2026-08-22T04:00:00+00:00"},
			{"kind":"weekly_all","percent":20,"resets_at":"2026-08-25T12:00:00+00:00"}]}`))
	}))
	defer srv.Close()
	s, err := FetchClaude(context.Background(), writeCredentials(t, "tok"), srv.URL, srv.Client(), time.Now())
	if err != nil {
		t.Fatalf("FetchClaude: %v", err)
	}
	if s.Fable != nil {
		t.Errorf("Fable = %+v, want nil", s.Fable)
	}
}

func TestFetchClaudeHTTPError(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()
	_, err := FetchClaude(context.Background(), writeCredentials(t, "expired"), srv.URL, srv.Client(), time.Now())
	if err == nil {
		t.Fatal("401 で err が nil")
	}
	// 今回の障害では Claude Code 本体がログイン済みでも usage API だけが401になった。
	// ログイン失効と断定せず、再試行後に復旧手順を出す契約を固定する。
	if requests != 2 {
		t.Errorf("request数 = %d, want 2", requests)
	}
	for _, want := range []string{"ログイン済み", "access token", "再試行", "claude auth login"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("401 の案内に %q が無い: %q", want, err)
		}
	}
}

func TestFetchClaudeRetriesWithUpdatedCredentials(t *testing.T) {
	credentials := writeCredentials(t, "old-token")
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests == 1 {
			if err := os.WriteFile(credentials, []byte(`{"claudeAiOauth":{"accessToken":"new-token"}}`), 0o600); err != nil {
				t.Error(err)
			}
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if got := r.Header.Get("Authorization"); got != "Bearer new-token" {
			t.Errorf("再試行のAuthorization = %q", got)
		}
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()

	if _, err := FetchClaude(context.Background(), credentials, srv.URL, srv.Client(), time.Now()); err != nil {
		t.Fatalf("credentials更新後の再試行: %v", err)
	}
	if requests != 2 {
		t.Errorf("request数 = %d, want 2", requests)
	}
}

func TestFetchClaudeRetriesServerError(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte(claudeUsageJSON))
	}))
	defer srv.Close()

	if _, err := FetchClaude(context.Background(), writeCredentials(t, "tok"), srv.URL, srv.Client(), time.Now()); err != nil {
		t.Fatalf("503後の再試行: %v", err)
	}
	if requests != 2 {
		t.Errorf("request数 = %d, want 2", requests)
	}
}

func TestFetchClaudeDoesNotRetryClientError(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()

	_, err := FetchClaude(context.Background(), writeCredentials(t, "tok"), srv.URL, srv.Client(), time.Now())
	if err == nil {
		t.Fatal("403 で err が nil")
	}
	if requests != 1 {
		t.Errorf("request数 = %d, want 1", requests)
	}
	if strings.Contains(err.Error(), "再試行") {
		t.Errorf("再試行しない403の案内が不正: %q", err)
	}
}

func TestFetchClaudeMissingCredentials(t *testing.T) {
	if _, err := FetchClaude(context.Background(), filepath.Join(t.TempDir(), "none.json"), "http://unused", http.DefaultClient, time.Now()); err == nil {
		t.Error("credentials 無しで err が nil")
	}
}

func TestFetchClaudeEmptyLimits(t *testing.T) {
	// エンドポイントの仕様変更で limits が消えたら旧値温存に倒すため err にする
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"limits":[]}`))
	}))
	defer srv.Close()
	if _, err := FetchClaude(context.Background(), writeCredentials(t, "tok"), srv.URL, srv.Client(), time.Now()); err == nil {
		t.Error("空 limits で err が nil")
	}
}
