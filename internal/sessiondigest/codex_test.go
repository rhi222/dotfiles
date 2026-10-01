package sessiondigest

// 不変条件: Codex rolloutから user / assistant の本文だけが残る。
// developerロール・AGENTS.mdの注入・environment_context・message以外のitemは混ざらない。

import (
	"strings"
	"testing"
)

func TestParseCodexKeepsOnlyDialogue(t *testing.T) {
	log := strings.Join([]string{
		`{"timestamp":"2026-09-30T03:16:53Z","type":"session_meta","payload":{"id":"c1","cwd":"/repo/b"}}`,
		`{"timestamp":"2026-09-30T03:16:54Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<skills_instructions>"}]}}`,
		`{"timestamp":"2026-09-30T03:16:55Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\n..."},{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}`,
		`{"timestamp":"2026-09-30T03:17:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"会議体の整理を手伝って"}]}}`,
		`{"timestamp":"2026-09-30T03:17:05Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}`,
		`{"timestamp":"2026-09-30T03:17:10Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"定例は週1です"}]}}`,
		`{"timestamp":"2026-09-30T03:17:11Z","type":"event_msg","payload":{"type":"agent_message","message":"dup"}}`,
	}, "\n")

	s, skipped, err := ParseCodex(strings.NewReader(log), mustDay(t, "2026-09-30", utc))
	if err != nil {
		t.Fatal(err)
	}
	if skipped != 0 {
		t.Errorf("skipped = %d", skipped)
	}
	if s.Source != "codex" || s.SessionID != "c1" || s.Cwd != "/repo/b" {
		t.Errorf("meta = %+v", s)
	}
	var got []string
	for _, tr := range s.Turns {
		got = append(got, tr.Role+":"+tr.Text)
	}
	want := []string{"user:会議体の整理を手伝って", "assistant:定例は週1です"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("turns = %q, want %q", got, want)
	}
}

func TestParseCodexDropsOtherDays(t *testing.T) {
	log := `{"timestamp":"2026-09-29T03:17:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"前日"}]}}`
	s, _, err := ParseCodex(strings.NewReader(log), mustDay(t, "2026-09-30", utc))
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Turns) != 0 {
		t.Errorf("turns = %+v", s.Turns)
	}
}
