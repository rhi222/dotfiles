package sessiondigest

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

// IndexEntry は stdout に出す索引の1行。skill はこれを見て subagent に file を渡す。
type IndexEntry struct {
	File      string `json:"file"`
	Source    string `json:"source"`
	SessionID string `json:"session_id"`
	Cwd       string `json:"cwd"`
	StartedAt string `json:"started_at"`
	UserTurns int    `json:"user_turns"`
	Chars     int    `json:"chars"`
}

// WriteDigest は session を Markdown にして dir/<source>-<id>.md に書く。
// **JSON ではなく Markdown にする。** subagent が Read の offset で分割して読めるようにするため。
func WriteDigest(dir string, s Session) (IndexEntry, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s session %s\n\n- cwd: %s\n- started_at: %s\n", s.Source, s.SessionID, s.Cwd, s.StartedAt().Format(time.RFC3339))
	chars := 0
	for _, t := range s.Turns {
		fmt.Fprintf(&b, "\n## %s (%s)\n\n%s\n", t.Role, t.At.Format("15:04"), t.Text)
		chars += utf8.RuneCountInString(t.Text)
	}
	path := filepath.Join(dir, s.Source+"-"+filepath.Base(s.SessionID)+".md")
	if err := os.WriteFile(path, []byte(b.String()), 0o600); err != nil {
		return IndexEntry{}, err
	}
	return IndexEntry{
		File: path, Source: s.Source, SessionID: s.SessionID, Cwd: s.Cwd,
		StartedAt: s.StartedAt().Format(time.RFC3339), UserTurns: s.UserTurns(), Chars: chars,
	}, nil
}

// CleanDigests は WriteDigest が書いた <source>-*.md だけを消し、空になった dir を外す。
// **他のファイルは消さない。** 誤った dir を渡されても被害を digest に限るため、
// 残ったファイルがあれば dir は残してエラーを返す。
func CleanDigests(dir string) error {
	for _, pattern := range []string{"claude-*.md", "codex-*.md"} {
		files, _ := filepath.Glob(filepath.Join(dir, pattern))
		for _, f := range files {
			if err := os.Remove(f); err != nil {
				return err
			}
		}
	}
	return os.Remove(dir)
}
