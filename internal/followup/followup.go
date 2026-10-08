// Package followup は、Linearの未完了issueに貼られたSlackスレを対象に、
// 最新発言が前回から進んだかを比べて一覧mdと通知文を作る。
//
// 何を追うかはLinear（自分が起票したもの）、スレを読むのはskill、
// 前回と何が違うかはここ、と分ける。判断はどこにも無い。
package followup

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type LinearIssue struct {
	Identifier  string `json:"identifier"`
	Title       string `json:"title"`
	URL         string `json:"url"`
	Description string `json:"description"`
}

type Issue struct {
	Identifier string `json:"identifier"`
	Title      string `json:"title"`
	URL        string `json:"url"`
}

// Target は追うスレ1本。key は slack:<channel>/<thread_ts>。
type Target struct {
	Key      string  `json:"key"`
	Channel  string  `json:"channel"`
	ThreadTS string  `json:"thread_ts"`
	URL      string  `json:"url"`
	Issues   []Issue `json:"issues"`
}

// Prompt は skill に渡す読み取り指示。Oldest は slack_read_thread の oldest（排他）。
type Prompt struct {
	Key      string `json:"key"`
	Channel  string `json:"channel"`
	ThreadTS string `json:"thread_ts"`
	Oldest   string `json:"oldest"`
}

type Message struct {
	TS     string `json:"ts"`
	ByID   string `json:"by_id"`
	ByName string `json:"by_name"`
	Text   string `json:"text"`
}

// Thread は skill が読んだ1本。読めなかったスレは Error で返し、前回の状態を保つ。
type Thread struct {
	Key    string  `json:"key"`
	Latest Message `json:"latest"`
	Error  bool    `json:"error,omitempty"`
}

type Input struct {
	Me      string   `json:"me"`
	Threads []Thread `json:"threads"`
}

// State は key → 前回までに見た最新発言。
type State map[string]Message

type Entry struct {
	Target
	Latest Message
	Mine   bool
	New    bool
	Unread bool // 今回読めず、前回の状態も無い
}

type Result struct {
	Entries []Entry
	State   State
	New     int
}

var slackURL = regexp.MustCompile(`(?i:https://[a-z0-9.-]+\.slack\.com)/archives/([A-Z0-9]+)/p(\d{10})(\d{6})(\?[^\s)\]>]*)?`)
var threadTSParam = regexp.MustCompile(`[?&]thread_ts=(\d+\.\d+)`)

// ExtractTargets はissue本文のSlack URLをスレ単位にまとめる。順序は初出順。
func ExtractTargets(issues []LinearIssue) []Target {
	var out []Target
	idx := map[string]int{}
	for _, is := range issues {
		for _, m := range slackURL.FindAllStringSubmatch(is.Description, -1) {
			ts := m[2] + "." + m[3]
			if p := threadTSParam.FindStringSubmatch(strings.ReplaceAll(m[4], "&amp;", "&")); p != nil {
				ts = p[1]
			}
			key := "slack:" + m[1] + "/" + ts
			ref := Issue{is.Identifier, is.Title, is.URL}
			i, ok := idx[key]
			if !ok {
				idx[key] = len(out)
				out = append(out, Target{Key: key, Channel: m[1], ThreadTS: ts, URL: m[0], Issues: []Issue{ref}})
				continue
			}
			if !hasIssue(out[i].Issues, is.Identifier) {
				out[i].Issues = append(out[i].Issues, ref)
			}
		}
	}
	return out
}

func hasIssue(is []Issue, id string) bool {
	for _, i := range is {
		if i.Identifier == id {
			return true
		}
	}
	return false
}

// Prompts は前回の最新tsを oldest にして、動きの無いスレを親だけで済ませる。
func Prompts(ts []Target, st State) []Prompt {
	out := make([]Prompt, 0, len(ts))
	for _, t := range ts {
		oldest := t.ThreadTS
		if m, ok := st[t.Key]; ok && m.TS != "" {
			oldest = m.TS
		}
		out = append(out, Prompt{t.Key, t.Channel, t.ThreadTS, oldest})
	}
	return out
}

// ParseInput は skill の出力を読む。threads の欠落は欠けた結果とみなして弾く。
func ParseInput(b []byte) (Input, error) {
	var probe map[string]json.RawMessage
	if err := json.Unmarshal(b, &probe); err != nil {
		return Input{}, err
	}
	if _, ok := probe["threads"]; !ok {
		return Input{}, errors.New("threads がない")
	}
	var in Input
	err := json.Unmarshal(b, &in)
	return in, err
}

// tsAfter は Slack ts（秒.マイクロ秒）を比べる。float だと桁落ちしうるので分けて比べる。
func tsAfter(a, b string) bool {
	as, au := splitTS(a)
	bs, bu := splitTS(b)
	return as > bs || (as == bs && au > bu)
}

func splitTS(ts string) (int64, int64) {
	s, u, _ := strings.Cut(ts, ".")
	si, _ := strconv.ParseInt(s, 10, 64)
	ui, _ := strconv.ParseInt((u + "000000")[:6], 10, 64)
	return si, ui
}

// Apply は targets と skill の出力を突き合わせる。全スレが揃っていなければ失敗する
// （欠けた結果で状態を上書きすると、次回に全件が🆕になったり消えたりする）。
func Apply(in Input, targets []Target, prev State, firstRun bool) (Result, error) {
	if in.Me == "" {
		return Result{}, errors.New("me がない")
	}
	got := map[string]Thread{}
	for _, th := range in.Threads {
		if !th.Error && th.Latest.TS == "" {
			return Result{}, fmt.Errorf("%s: latest.ts がない", th.Key)
		}
		got[th.Key] = th
	}
	known := map[string]bool{}
	for _, t := range targets {
		known[t.Key] = true
		if _, ok := got[t.Key]; !ok {
			return Result{}, fmt.Errorf("%s: 読んだ結果がない", t.Key)
		}
	}
	for k := range got {
		if !known[k] {
			return Result{}, fmt.Errorf("%s: 対象に無いkey", k)
		}
	}
	r := Result{State: State{}}
	for _, t := range targets {
		th := got[t.Key]
		old, seen := prev[t.Key]
		if th.Error {
			if seen {
				r.State[t.Key] = old
			}
			r.Entries = append(r.Entries, Entry{Target: t, Latest: old, Mine: seen && old.ByID == in.Me, Unread: !seen})
			continue
		}
		cur := th.Latest
		advanced := !seen || tsAfter(cur.TS, old.TS)
		if !advanced {
			cur = old
		}
		e := Entry{Target: t, Latest: cur, Mine: cur.ByID == in.Me}
		e.New = !firstRun && seen && advanced && !e.Mine
		if e.New {
			r.New++
		}
		r.State[t.Key] = cur
		r.Entries = append(r.Entries, e)
	}
	return r, nil
}

// Notice は toast の本文。🆕が無ければ空。
func Notice(r Result) string {
	if r.New == 0 {
		return ""
	}
	return fmt.Sprintf("動きあり%d件", r.New)
}

// Render は一覧mdを作る。時刻は at のタイムゾーンで出す。
func Render(r Result, at time.Time) string {
	es := append([]Entry(nil), r.Entries...)
	sort.SliceStable(es, func(i, j int) bool {
		if es[i].New != es[j].New {
			return es[i].New
		}
		return tsAfter(es[i].Latest.TS, es[j].Latest.TS)
	})
	var mine, theirs, unread []string
	for _, e := range es {
		mark := ""
		if e.New {
			mark = "🆕 "
		}
		ids := make([]string, len(e.Issues))
		for i, is := range e.Issues {
			ids[i] = is.Identifier
		}
		title := ""
		if len(e.Issues) > 0 {
			title = e.Issues[0].Title
		}
		if e.Unread {
			unread = append(unread, fmt.Sprintf("- %s %s %s", strings.Join(ids, ","), title, e.URL))
			continue
		}
		s, _ := splitTS(e.Latest.TS)
		line := fmt.Sprintf("- %s%s %s — %s %s「%s」 %s", mark, strings.Join(ids, ","), title,
			e.Latest.ByName, time.Unix(s, 0).In(at.Location()).Format("01/02 15:04"), e.Latest.Text, e.URL)
		if e.Mine {
			theirs = append(theirs, line)
		} else {
			mine = append(mine, line)
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# followup %s\n", at.Format("2006-01-02 15:04"))
	for _, s := range []struct {
		title string
		lines []string
	}{{"自分の番", mine}, {"相手待ち", theirs}} {
		fmt.Fprintf(&b, "\n## %s\n\n", s.title)
		if len(s.lines) == 0 {
			b.WriteString("- なし\n")
			continue
		}
		b.WriteString(strings.Join(s.lines, "\n") + "\n")
	}
	// 読めないスレは通知が止まっていることに気付けるよう、あるときだけ節を出す
	if len(unread) > 0 {
		b.WriteString("\n## 読めなかった\n\n" + strings.Join(unread, "\n") + "\n")
	}
	return b.String()
}

// Load は前回状態を読む。ファイルが無ければ初回として空を返す。
func Load(dir string) (State, bool, error) {
	var st State
	ok, err := readJSON(filepath.Join(dir, "state.json"), &st)
	if !ok || err != nil {
		return State{}, !ok && err == nil, err
	}
	return st, false, nil
}

func LoadTargets(dir string) ([]Target, error) {
	var ts []Target
	ok, err := readJSON(filepath.Join(dir, "targets.json"), &ts)
	if err == nil && !ok {
		err = errors.New("targets.json がない（先に dotctl followup targets を実行する）")
	}
	return ts, err
}

func SaveTargets(dir string, ts []Target) error {
	return writeJSON(dir, "targets.json", ts)
}

// Save は state.json と latest.md を書き換え、🆕があれば notice を上書きする。
// notice は cron が toast を出したあとに消す。🆕が無い実行では残す。
func Save(dir string, r Result, md string) error {
	if err := writeJSON(dir, "state.json", r.State); err != nil {
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

func readJSON(path string, v any) (bool, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, json.Unmarshal(b, v)
}

func writeJSON(dir, name string, v any) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(filepath.Join(dir, name), append(b, '\n'))
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
