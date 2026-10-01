package sessiondigest

// 不変条件: Claude JSONLから「人とagentが交わした本文」だけが残る。
// tool入出力・thinking・harnessの注入・subagent(sidechain)・別日の行は混ざらない。
// 混ざるとsubagentの判定が注入文やtool出力を知識と取り違える。

import (
	"strings"
	"testing"
	"time"
)

var utc = time.UTC

func mustDay(t *testing.T, date string, loc *time.Location) Day {
	t.Helper()
	d, err := NewDay(date, loc)
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func TestParseClaudeKeepsOnlyDialogue(t *testing.T) {
	log := strings.Join([]string{
		`{"type":"user","sessionId":"s1","cwd":"/repo/a","timestamp":"2026-09-30T01:00:00Z","message":{"role":"user","content":"予約APIの再送仕様を教えて"}}`,
		`{"type":"assistant","sessionId":"s1","cwd":"/repo/a","timestamp":"2026-09-30T01:00:05Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"再送は3回です"},{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}`,
		`{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:06Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"secret output"}]}}`,
		`{"type":"user","sessionId":"s1","isMeta":true,"timestamp":"2026-09-30T01:00:07Z","message":{"role":"user","content":"meta text"}}`,
		`{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:08Z","message":{"role":"user","content":"<system-reminder>injected</system-reminder>"}}`,
		`{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:09Z","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x"}]}}`,
		`{"type":"user","sessionId":"s1","isSidechain":true,"timestamp":"2026-09-30T01:00:10Z","message":{"role":"user","content":"sidechain"}}`,
		`{"type":"user","sessionId":"s1","timestamp":"2026-10-01T01:00:00Z","message":{"role":"user","content":"翌日の発言"}}`,
		`{"type":"attachment","timestamp":"2026-09-30T01:00:11Z"}`,
	}, "\n")

	s, skipped, err := ParseClaude(strings.NewReader(log), mustDay(t, "2026-09-30", utc))
	if err != nil {
		t.Fatal(err)
	}
	if skipped != 0 {
		t.Errorf("skipped = %d, want 0", skipped)
	}
	if s.Source != "claude" || s.SessionID != "s1" || s.Cwd != "/repo/a" {
		t.Errorf("meta = %+v", s)
	}
	var got []string
	for _, tr := range s.Turns {
		got = append(got, tr.Role+":"+tr.Text)
	}
	want := []string{"user:予約APIの再送仕様を教えて", "assistant:再送は3回です"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("turns = %q, want %q", got, want)
	}
	if s.UserTurns() != 1 {
		t.Errorf("UserTurns = %d", s.UserTurns())
	}
	if !s.StartedAt().Equal(time.Date(2026, 9, 30, 1, 0, 0, 0, utc)) {
		t.Errorf("StartedAt = %v", s.StartedAt())
	}
}

func TestParseClaudeCountsBrokenLines(t *testing.T) {
	log := "{broken\n" +
		`{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:00Z","message":{"role":"user","content":"ok"}}` + "\n"
	s, skipped, err := ParseClaude(strings.NewReader(log), mustDay(t, "2026-09-30", utc))
	if err != nil {
		t.Fatal(err)
	}
	if skipped != 1 || len(s.Turns) != 1 {
		t.Errorf("skipped = %d, turns = %d", skipped, len(s.Turns))
	}
}

// Review Focus: 15:30Z はJSTで翌日。ローカル時刻で日付を切る。
func TestParseClaudeUsesLocalDate(t *testing.T) {
	jst := time.FixedZone("JST", 9*3600)
	log := `{"type":"user","sessionId":"s1","timestamp":"2026-09-30T15:30:00Z","message":{"role":"user","content":"深夜の発言"}}`
	s, _, err := ParseClaude(strings.NewReader(log), mustDay(t, "2026-10-01", jst))
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Turns) != 1 {
		t.Errorf("turns = %d, want 1", len(s.Turns))
	}
}

// Review Focus: tool_resultを含む行は数MBになる。Scannerの64KB上限で落ちない。
func TestParseClaudeHandlesHugeLine(t *testing.T) {
	huge := strings.Repeat("x", 2<<20)
	log := `{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:00Z","message":{"role":"user","content":[{"type":"tool_result","content":"` + huge + `"}]}}` + "\n" +
		`{"type":"user","sessionId":"s1","timestamp":"2026-09-30T01:00:01Z","message":{"role":"user","content":"after"}}`
	s, skipped, err := ParseClaude(strings.NewReader(log), mustDay(t, "2026-09-30", utc))
	if err != nil {
		t.Fatal(err)
	}
	if skipped != 0 || len(s.Turns) != 1 || s.Turns[0].Text != "after" {
		t.Errorf("skipped = %d, turns = %+v", skipped, s.Turns)
	}
}

func TestNewDayRejectsBadDate(t *testing.T) {
	if _, err := NewDay("2026/09/30", utc); err == nil {
		t.Error("want error")
	}
}
