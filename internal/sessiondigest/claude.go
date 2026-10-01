package sessiondigest

import (
	"encoding/json"
	"io"
	"time"
)

type claudeLine struct {
	Type        string `json:"type"`
	SessionID   string `json:"sessionId"`
	Cwd         string `json:"cwd"`
	Timestamp   string `json:"timestamp"`
	IsMeta      bool   `json:"isMeta"`
	IsSidechain bool   `json:"isSidechain"`
	Message     struct {
		Content json.RawMessage `json:"content"`
	} `json:"message"`
}

type textBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// ParseClaude は ~/.claude/projects/<slug>/<uuid>.jsonl を1本読む。
func ParseClaude(r io.Reader, day Day) (Session, int, error) {
	s := Session{Source: "claude"}
	skipped, err := eachLine(r, func(b []byte) error {
		var l claudeLine
		if err := json.Unmarshal(b, &l); err != nil {
			return err
		}
		if l.Type != "user" && l.Type != "assistant" {
			return nil
		}
		if s.SessionID == "" {
			s.SessionID = l.SessionID
		}
		if s.Cwd == "" {
			s.Cwd = l.Cwd
		}
		if l.IsMeta || l.IsSidechain {
			return nil
		}
		at, err := time.Parse(time.RFC3339Nano, l.Timestamp)
		if err != nil || !day.Contains(at) {
			return nil
		}
		for _, text := range claudeTexts(l.Message.Content) {
			if keep(l.Type, text) {
				s.Turns = append(s.Turns, Turn{Role: l.Type, Text: text, At: at})
			}
		}
		return nil
	})
	return s, skipped, err
}

// claudeTexts は content（文字列またはblock配列）から text block だけを取り出す。
func claudeTexts(raw json.RawMessage) []string {
	var str string
	if json.Unmarshal(raw, &str) == nil {
		return []string{str}
	}
	var blocks []textBlock
	if json.Unmarshal(raw, &blocks) != nil {
		return nil
	}
	var out []string
	for _, b := range blocks {
		if b.Type == "text" {
			out = append(out, b.Text)
		}
	}
	return out
}
