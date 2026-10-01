package sessiondigest

// 不変条件: 当日に発言があるsessionだけが、user発言の閾値を満たした場合に、
// 開始時刻順で返る。subagentのログは読まない。Codexの前日ディレクトリも読む。
// digestは1 session 1ファイルで、ファイル名が空にならない。

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func claudeUser(id, ts, text string) string {
	return fmt.Sprintf(`{"type":"user","sessionId":%q,"cwd":"/repo/a","timestamp":%q,"message":{"role":"user","content":%q}}`, id, ts, text) + "\n"
}

func codexUser(ts, text string) string {
	return fmt.Sprintf(`{"timestamp":%q,"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":%q}]}}`, ts, text) + "\n"
}

func TestCollect(t *testing.T) {
	root := t.TempDir()
	claudeRoot := filepath.Join(root, "claude")
	codexRoot := filepath.Join(root, "codex")

	// 当日3発言（採用）
	writeFile(t, filepath.Join(claudeRoot, "projects", "p1", "late.jsonl"),
		claudeUser("late", "2026-09-30T05:00:00Z", "a")+claudeUser("late", "2026-09-30T05:01:00Z", "b")+claudeUser("late", "2026-09-30T05:02:00Z", "c"))
	// 当日1発言（閾値未満で除外）
	writeFile(t, filepath.Join(claudeRoot, "projects", "p1", "short.jsonl"),
		claudeUser("short", "2026-09-30T02:00:00Z", "a"))
	// subagentのログ（読まない）
	writeFile(t, filepath.Join(claudeRoot, "projects", "p1", "late", "subagents", "agent-x.jsonl"),
		claudeUser("sub", "2026-09-30T01:00:00Z", "a")+claudeUser("sub", "2026-09-30T01:01:00Z", "b")+claudeUser("sub", "2026-09-30T01:02:00Z", "c"))
	// Review Focus: 前日ディレクトリのCodex sessionで当日にも発言がある（採用、先頭）。
	// session_metaが無いのでidはファイル名から補う。
	writeFile(t, filepath.Join(codexRoot, "sessions", "2026", "09", "29", "rollout-early.jsonl"),
		codexUser("2026-09-29T23:00:00Z", "前日")+codexUser("2026-09-30T00:10:00Z", "x")+codexUser("2026-09-30T00:11:00Z", "y")+codexUser("2026-09-30T00:12:00Z", "z")+"{broken\n")

	day, err := NewDay("2026-09-30", utc)
	if err != nil {
		t.Fatal(err)
	}
	res, err := Collect(Options{ClaudeRoot: claudeRoot, CodexRoot: codexRoot, Day: day, MinUserTurns: 3})
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, s := range res.Sessions {
		ids = append(ids, s.Source+":"+s.SessionID)
	}
	if got, want := strings.Join(ids, ","), "codex:rollout-early,claude:late"; got != want {
		t.Errorf("sessions = %s, want %s", got, want)
	}
	if res.Skipped != 1 {
		t.Errorf("skipped = %d, want 1", res.Skipped)
	}
}

// Review Focus: Codexのディレクトリが無い端末でもClaudeだけで続ける。
func TestCollectWithoutCodexDir(t *testing.T) {
	root := t.TempDir()
	claudeRoot := filepath.Join(root, "claude")
	writeFile(t, filepath.Join(claudeRoot, "projects", "p1", "s.jsonl"), claudeUser("s", "2026-09-30T05:00:00Z", "a"))
	day, _ := NewDay("2026-09-30", utc)
	res, err := Collect(Options{ClaudeRoot: claudeRoot, CodexRoot: filepath.Join(root, "missing"), Day: day, MinUserTurns: 1})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Sessions) != 1 {
		t.Errorf("sessions = %d", len(res.Sessions))
	}
}

func TestWriteDigest(t *testing.T) {
	dir := t.TempDir()
	day, _ := NewDay("2026-09-30", utc)
	s, _, err := ParseClaude(strings.NewReader(claudeUser("s1", "2026-09-30T05:00:00Z", "質問です")), day)
	if err != nil {
		t.Fatal(err)
	}
	e, err := WriteDigest(dir, s)
	if err != nil {
		t.Fatal(err)
	}
	if e.File != filepath.Join(dir, "claude-s1.md") || e.SessionID != "s1" || e.UserTurns != 1 || e.Chars != 4 {
		t.Errorf("entry = %+v", e)
	}
	body, err := os.ReadFile(e.File)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"s1", "/repo/a", "## user", "質問です"} {
		if !strings.Contains(string(body), want) {
			t.Errorf("digest lacks %q:\n%s", want, body)
		}
	}
}
