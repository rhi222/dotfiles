// Package followup は、Slack・Jiraから拾った返事待ちと頼まれ事を前回状態と比べ、
// 変わった件に🆕を付けて一覧mdと通知文を作る。
//
// 判断（何が返事待ちか）は skill 側、状態（前回と何が違うか）はここ、と分ける。
package followup

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// waitingWindow を過ぎた返事待ちは一覧から外す。
const waitingWindow = 7 * 24 * time.Hour

type Item struct {
	Key          string     `json:"key"`
	Kind         string     `json:"kind"` // waiting | asked
	Source       string     `json:"source"`
	Where        string     `json:"where"`
	Who          string     `json:"who"`
	Summary      string     `json:"summary"`
	URL          string     `json:"url"`
	Since        time.Time  `json:"since"`
	Replied      bool       `json:"replied,omitempty"`
	ReplyAt      *time.Time `json:"reply_at,omitempty"`
	ReplySummary string     `json:"reply_summary,omitempty"`
	UpdatedAt    *time.Time `json:"updated_at,omitempty"`
}

type Input struct {
	GeneratedAt time.Time `json:"generated_at"`
	Items       []Item    `json:"items"`
}

// State は key → 前回見たときの版。
type State map[string]string

type Entry struct {
	Item
	New bool
}

type Result struct {
	Entries    []Entry
	State      State
	NewReplies int
	NewAsked   int
}

// ParseInput は skill の出力を読む。欠けた入力で前回状態を上書きしないよう、
// generated_at と items の欠落、key の空、未知の kind を弾く。
func ParseInput(b []byte) (Input, error) {
	var probe map[string]json.RawMessage
	if err := json.Unmarshal(b, &probe); err != nil {
		return Input{}, err
	}
	if _, ok := probe["items"]; !ok {
		return Input{}, errors.New("items がない")
	}
	var in Input
	if err := json.Unmarshal(b, &in); err != nil {
		return Input{}, err
	}
	if in.GeneratedAt.IsZero() {
		return Input{}, errors.New("generated_at がない")
	}
	for i, it := range in.Items {
		if it.Key == "" {
			return Input{}, fmt.Errorf("items[%d]: key が空", i)
		}
		if it.Kind != "waiting" && it.Kind != "asked" {
			return Input{}, fmt.Errorf("items[%d]: 知らない kind: %q", i, it.Kind)
		}
	}
	return in, nil
}

func version(it Item) string {
	switch {
	case it.Kind == "waiting" && it.Replied && it.ReplyAt != nil:
		return "replied:" + it.ReplyAt.UTC().Format(time.RFC3339)
	case it.Kind == "waiting" && it.Replied:
		return "replied:"
	case it.Kind == "waiting":
		return "waiting"
	case it.UpdatedAt != nil:
		return "updated:" + it.UpdatedAt.UTC().Format(time.RFC3339)
	default:
		return "seen"
	}
}

// Apply は前回状態と比べて🆕を判定する。firstRun では何も🆕にしない。
func Apply(in Input, prev State, firstRun bool) Result {
	r := Result{State: State{}}
	cutoff := in.GeneratedAt.Add(-waitingWindow)
	for _, it := range in.Items {
		if _, dup := r.State[it.Key]; dup {
			continue
		}
		if it.Kind == "waiting" && it.Since.Before(cutoff) {
			continue
		}
		v := version(it)
		old, seen := prev[it.Key]
		changed := !seen || old != v
		isNew := false
		if !firstRun {
			if it.Kind == "waiting" {
				isNew = it.Replied && changed
			} else {
				isNew = changed
			}
		}
		if isNew {
			if it.Kind == "waiting" {
				r.NewReplies++
			} else {
				r.NewAsked++
			}
		}
		r.State[it.Key] = v
		r.Entries = append(r.Entries, Entry{Item: it, New: isNew})
	}
	return r
}

// Notice は toast の本文。🆕が無ければ空。
func Notice(r Result) string {
	if r.NewReplies+r.NewAsked == 0 {
		return ""
	}
	return fmt.Sprintf("返事%d件・頼まれ事%d件", r.NewReplies, r.NewAsked)
}

// Render は一覧mdを作る。
func Render(r Result, at time.Time) string {
	var replied, waiting, asked []string
	for _, e := range r.Entries {
		mark := ""
		if e.New {
			mark = "🆕 "
		}
		days := int(at.Sub(e.Since).Hours() / 24)
		who := ""
		if e.Who != "" {
			who = " " + e.Who
		}
		switch {
		case e.Kind == "waiting" && e.Replied:
			replied = append(replied, fmt.Sprintf("- %s[%s]%s「%s」 ← %s 自分「%s」 %s",
				mark, e.Where, who, e.ReplySummary, e.Since.Format("01/02"), e.Summary, e.URL))
		case e.Kind == "waiting":
			waiting = append(waiting, fmt.Sprintf("- [%s]%s %d日経過「%s」 %s", e.Where, who, days, e.Summary, e.URL))
		default:
			asked = append(asked, fmt.Sprintf("- %s[%s]%s %d日経過「%s」 %s", mark, e.Where, who, days, e.Summary, e.URL))
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# followup %s\n", at.Format("2006-01-02 15:04"))
	for _, s := range []struct {
		title string
		lines []string
	}{{"返事が来た", replied}, {"返事待ち", waiting}, {"頼まれ事", asked}} {
		fmt.Fprintf(&b, "\n## %s\n\n", s.title)
		if len(s.lines) == 0 {
			b.WriteString("- なし\n")
			continue
		}
		b.WriteString(strings.Join(s.lines, "\n") + "\n")
	}
	return b.String()
}

// Load は前回状態を読む。ファイルが無ければ初回として空を返す。
func Load(dir string) (State, bool, error) {
	b, err := os.ReadFile(filepath.Join(dir, "state.json"))
	if errors.Is(err, os.ErrNotExist) {
		return State{}, true, nil
	}
	if err != nil {
		return nil, false, err
	}
	var st State
	if err := json.Unmarshal(b, &st); err != nil {
		return nil, false, err
	}
	return st, false, nil
}

// Save は state.json と latest.md を書き換え、🆕があれば notice を上書きする。
// notice は cron が toast を出したあとに消す。🆕が無い実行では残す。
func Save(dir string, r Result, md string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	st, err := json.MarshalIndent(r.State, "", "  ")
	if err != nil {
		return err
	}
	if err := writeAtomic(filepath.Join(dir, "state.json"), append(st, '\n')); err != nil {
		return err
	}
	if err := writeAtomic(filepath.Join(dir, "latest.md"), []byte(md)); err != nil {
		return err
	}
	if n := Notice(r); n != "" {
		return writeAtomic(filepath.Join(dir, "notice"), []byte(n+"\n"))
	}
	return nil
}

func writeAtomic(path string, b []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), path)
}
