package command

// 不変条件: dotctl session digest は索引をstdoutへ、digest本文を--out-dirへ出す。
// 壊れた行があれば機械可読な契約行 session-digest: SKIPPED=N をstderrへ出す。
// 引数が足りなければ終了コード2で、何も書かない。

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func digestEnv(t *testing.T) (Env, *bytes.Buffer, *bytes.Buffer, string) {
	t.Helper()
	root := t.TempDir()
	claudeRoot := filepath.Join(root, "claude")
	dir := filepath.Join(claudeRoot, "projects", "p1")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	line := `{"type":"user","sessionId":"s1","cwd":"/repo/a","timestamp":"2026-09-30T05:00:00Z","message":{"role":"user","content":"q"}}`
	body := line + "\n" + line + "\n" + line + "\n{broken\n"
	if err := os.WriteFile(filepath.Join(dir, "s1.jsonl"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	env := Env{
		Stdout: &out, Stderr: &errb,
		SessionDigestClaudeRoot: claudeRoot,
		SessionDigestCodexRoot:  filepath.Join(root, "codex"),
		Location:                time.UTC,
	}
	return env, &out, &errb, root
}

func TestSessionDigest(t *testing.T) {
	env, out, errb, root := digestEnv(t)
	outDir := filepath.Join(root, "out")
	code := Run(context.Background(), []string{"session", "digest", "--date", "2026-09-30", "--out-dir", outDir}, env)
	if code != 0 {
		t.Fatalf("exit = %d, stderr = %s", code, errb)
	}
	var e struct {
		File      string `json:"file"`
		SessionID string `json:"session_id"`
		UserTurns int    `json:"user_turns"`
	}
	if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &e); err != nil {
		t.Fatalf("stdout = %q: %v", out, err)
	}
	if e.SessionID != "s1" || e.UserTurns != 3 {
		t.Errorf("entry = %+v", e)
	}
	if _, err := os.Stat(e.File); err != nil {
		t.Errorf("digest file: %v", err)
	}
	if !strings.Contains(errb.String(), "session-digest: SKIPPED=1") {
		t.Errorf("stderr = %q", errb)
	}
}

func TestSessionDigestNoSessions(t *testing.T) {
	env, out, _, root := digestEnv(t)
	code := Run(context.Background(), []string{"session", "digest", "--date", "2026-01-01", "--out-dir", filepath.Join(root, "out")}, env)
	if code != 0 || out.Len() != 0 {
		t.Errorf("exit = %d, stdout = %q", code, out)
	}
}

func TestSessionDigestUsage(t *testing.T) {
	env, _, _, _ := digestEnv(t)
	for _, args := range [][]string{
		{"session", "digest", "--out-dir", "/x"},
		{"session", "digest", "--date", "2026-09-30"},
		{"session", "digest", "--date", "bad", "--out-dir", "/x"},
	} {
		if code := Run(context.Background(), args, env); code != 2 {
			t.Errorf("%v: exit = %d, want 2", args, code)
		}
	}
}

func TestSessionDigestReportsUnreadable(t *testing.T) {
	env, _, errb, root := digestEnv(t)
	if err := os.MkdirAll(filepath.Join(root, "claude", "projects", "p1", "bad.jsonl"), 0o755); err != nil {
		t.Fatal(err)
	}
	code := Run(context.Background(), []string{"session", "digest", "--date", "2026-09-30", "--out-dir", filepath.Join(root, "out")}, env)
	if code != 0 {
		t.Fatalf("exit = %d, stderr = %s", code, errb)
	}
	if !strings.Contains(errb.String(), "UNREADABLE=1") {
		t.Errorf("stderr = %q", errb)
	}
}

func TestSessionDigestClean(t *testing.T) {
	env, _, errb, root := digestEnv(t)
	outDir := filepath.Join(root, "out")
	if code := Run(context.Background(), []string{"session", "digest", "--date", "2026-09-30", "--out-dir", outDir}, env); code != 0 {
		t.Fatalf("digest exit = %d", code)
	}
	if code := Run(context.Background(), []string{"session", "digest-clean", outDir}, env); code != 0 {
		t.Fatalf("clean exit = %d, stderr = %s", code, errb)
	}
	if _, err := os.Stat(outDir); !os.IsNotExist(err) {
		t.Errorf("out dir remains: %v", err)
	}
}
