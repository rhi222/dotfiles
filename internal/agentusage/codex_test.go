package agentusage

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// rollout の1行。rate_limits は payload の下に埋まっている（実ログと同じ入れ子）
func rlLine(usedPercent string, windowMinutes, resetsAt string) string {
	return `{"timestamp":"2026-08-21T21:54:43Z","type":"event_msg","payload":{"type":"token_count",` +
		`"rate_limits":{"primary":{"used_percent":` + usedPercent + `,"window_minutes":` + windowMinutes +
		`,"resets_at":` + resetsAt + `},"secondary":null,"plan_type":"plus"}}}`
}

func writeRollout(t *testing.T, dir, name string, lines []string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, name)
	body := ""
	for _, l := range lines {
		body += l + "\n"
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFetchCodex(t *testing.T) {
	root := t.TempDir()
	day := filepath.Join(root, "2026", "08", "21")
	writeRollout(t, day, "rollout-2026-08-21T21-54-43-abc.jsonl", []string{
		`{"type":"session_meta","payload":{}}`,
		rlLine("1.0", "10080", "1787950000"), // 古い方
		`{"type":"response_item","payload":{}}`,
		rlLine("2.0", "10080", "1787957065"), // 最後の出現 → これを採る
	})
	s, err := FetchCodex(root, time.Unix(1787900000, 0))
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly == nil || s.Weekly.Percent != 2 {
		t.Errorf("Weekly = %+v, want percent 2", s.Weekly)
	}
	if s.Weekly.ResetsAt != 1787957065 {
		t.Errorf("ResetsAt = %d", s.Weekly.ResetsAt)
	}
	if s.FetchedAt != 1787900000 {
		t.Errorf("FetchedAt = %d", s.FetchedAt)
	}
}

func TestFetchCodexSecondaryWeekly(t *testing.T) {
	// primary が 5h 窓・secondary が weekly のアカウント → secondary を採る
	root := t.TempDir()
	day := filepath.Join(root, "2026", "08", "21")
	line := `{"type":"event_msg","payload":{"rate_limits":{` +
		`"primary":{"used_percent":80.0,"window_minutes":300,"resets_at":1787910000},` +
		`"secondary":{"used_percent":33.4,"window_minutes":10080,"resets_at":1787957065}}}}`
	writeRollout(t, day, "rollout-a.jsonl", []string{line})
	s, err := FetchCodex(root, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 33 { // 33.4 → 四捨五入で 33
		t.Errorf("Weekly.Percent = %d, want 33", s.Weekly.Percent)
	}
}

func TestFetchCodexNewestFileWins(t *testing.T) {
	root := t.TempDir()
	old := filepath.Join(root, "2026", "08", "20")
	newer := filepath.Join(root, "2026", "08", "21")
	oldPath := writeRollout(t, old, "rollout-old.jsonl", []string{rlLine("9.0", "10080", "100")})
	writeRollout(t, newer, "rollout-new.jsonl", []string{rlLine("2.0", "10080", "200")})
	// mtime を明示して順序を固定する
	os.Chtimes(oldPath, time.Unix(1000, 0), time.Unix(1000, 0))
	s, err := FetchCodex(root, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 2 {
		t.Errorf("Weekly.Percent = %d, want 2（新しいファイルの値）", s.Weekly.Percent)
	}
}

func TestFetchCodexSkipsFileWithoutRateLimits(t *testing.T) {
	// 最新ファイルに rate_limits が無ければ次のファイルへ落ちる
	root := t.TempDir()
	day := filepath.Join(root, "2026", "08", "21")
	withRL := writeRollout(t, day, "rollout-a.jsonl", []string{rlLine("5.0", "10080", "300")})
	os.Chtimes(withRL, time.Unix(1000, 0), time.Unix(1000, 0))
	writeRollout(t, day, "rollout-b.jsonl", []string{`{"type":"session_meta","payload":{}}`})
	s, err := FetchCodex(root, time.Now())
	if err != nil {
		t.Fatalf("FetchCodex: %v", err)
	}
	if s.Weekly.Percent != 5 {
		t.Errorf("Weekly.Percent = %d, want 5", s.Weekly.Percent)
	}
}

func TestFetchCodexEmpty(t *testing.T) {
	if _, err := FetchCodex(t.TempDir(), time.Now()); err == nil {
		t.Error("セッション無しで err が nil")
	}
}
