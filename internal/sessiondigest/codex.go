package sessiondigest

import (
	"encoding/json"
	"io"
	"time"
)

type codexLine struct {
	Timestamp string          `json:"timestamp"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

type codexMeta struct {
	ID  string `json:"id"`
	Cwd string `json:"cwd"`
}

type codexMessage struct {
	Type    string      `json:"type"`
	Role    string      `json:"role"`
	Content []textBlock `json:"content"`
}

// ParseCodex は ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl を1本読む。
// 本文の正典は response_item。event_msg は同じ内容の重複なので読まない。
func ParseCodex(r io.Reader, day Day) (Session, int, error) {
	s := Session{Source: "codex"}
	skipped, err := eachLine(r, func(b []byte) error {
		var l codexLine
		if err := json.Unmarshal(b, &l); err != nil {
			return err
		}
		switch l.Type {
		case "session_meta":
			var m codexMeta
			if err := json.Unmarshal(l.Payload, &m); err != nil {
				return err
			}
			s.SessionID, s.Cwd = m.ID, m.Cwd
		case "response_item":
			var m codexMessage
			if err := json.Unmarshal(l.Payload, &m); err != nil {
				return err
			}
			if m.Type != "message" || (m.Role != "user" && m.Role != "assistant") {
				return nil
			}
			at, err := time.Parse(time.RFC3339Nano, l.Timestamp)
			if err != nil || !day.Contains(at) {
				return nil
			}
			for _, c := range m.Content {
				if (c.Type == "input_text" || c.Type == "output_text") && keep(m.Role, c.Text) {
					s.Turns = append(s.Turns, Turn{Role: m.Role, Text: c.Text, At: day.local(at)})
				}
			}
		}
		return nil
	})
	return s, skipped, err
}
