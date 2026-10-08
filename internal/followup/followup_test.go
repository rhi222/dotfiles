package followup

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

const ws = "https://example.slack.com/archives/"

func TestExtractTargets(t *testing.T) {
	issues := []LinearIssue{
		{Identifier: "NSY-1", Title: "a", URL: "https://linear.example/1", State: LinearState{"Waiting"},
			Description: "元: [" + ws + "C1/p1788425240728449](" + ws + "C1/p1788425240728449)"},
		{Identifier: "NSY-2", Title: "b", URL: "https://linear.example/2", State: LinearState{"Todo"},
			Description: ws + "C2/p1790679401148219?thread_ts=1790677055.034899&cid=C2 と " + ws + "C1/p1788425240728449"},
		{Identifier: "NSY-3", Title: "c", Description: "URLなし"},
	}
	got := ExtractTargets(issues)
	want := []Target{
		{Key: "slack:C1/1788425240.728449", Channel: "C1", ThreadTS: "1788425240.728449",
			URL:    ws + "C1/p1788425240728449",
			Issues: []Issue{{"NSY-1", "a", "https://linear.example/1", "Waiting"}, {"NSY-2", "b", "https://linear.example/2", "Todo"}}},
		{Key: "slack:C2/1790677055.034899", Channel: "C2", ThreadTS: "1790677055.034899",
			URL:    ws + "C2/p1790679401148219?thread_ts=1790677055.034899&cid=C2",
			Issues: []Issue{{"NSY-2", "b", "https://linear.example/2", "Todo"}}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got  %+v\nwant %+v", got, want)
	}
}

func TestPromptsUsesStateTSAsOldest(t *testing.T) {
	ts := []Target{
		{Key: "slack:C1/1.000001", Channel: "C1", ThreadTS: "1.000001"},
		{Key: "slack:C2/2.000002", Channel: "C2", ThreadTS: "2.000002"},
	}
	st := State{"slack:C1/1.000001": {TS: "5.000005"}}
	got := Prompts(ts, st)
	want := []Prompt{
		{Key: "slack:C1/1.000001", Channel: "C1", ThreadTS: "1.000001", Oldest: "5.000005"},
		{Key: "slack:C2/2.000002", Channel: "C2", ThreadTS: "2.000002", Oldest: "2.000002"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v", got)
	}
}

var targets = []Target{
	{Key: "k1", URL: "u1", Issues: []Issue{{"NSY-1", "t1", "", "Todo"}}},
	{Key: "k2", URL: "u2", Issues: []Issue{{"NSY-2", "t2", "", "Waiting"}}},
	{Key: "k3", URL: "u3", Issues: []Issue{{"NSY-3", "t3", "", "In Progress"}}},
}

func msg(ts, by string) Message { return Message{TS: ts, ByID: by, ByName: by, Text: "x"} }

func input(m1, m2 Message) Input {
	return Input{Me: "ME", Threads: []Thread{{Key: "k1", Latest: m1}, {Key: "k2", Latest: m2}}}
}

func TestApplyFirstRunHasNoNew(t *testing.T) {
	r, err := Apply(input(msg("10.000000", "A"), msg("10.000000", "ME")), targets[:2], State{}, true)
	if err != nil {
		t.Fatal(err)
	}
	if r.New != 0 || Notice(r) != "" {
		t.Fatalf("new=%d", r.New)
	}
	if !r.Entries[1].Mine || r.Entries[0].Mine {
		t.Fatalf("mine wrong: %+v", r.Entries)
	}
}

func TestApplyNewOnlyWhenOtherSpeaksLater(t *testing.T) {
	prev := State{"k1": msg("10.000000", "ME"), "k2": msg("10.000000", "A")}
	r, err := Apply(input(msg("11.000000", "A"), msg("12.000000", "ME")), targets[:2], prev, false)
	if err != nil {
		t.Fatal(err)
	}
	if !r.Entries[0].New || r.Entries[1].New {
		t.Fatalf("entries %+v", r.Entries)
	}
	if Notice(r) != "動きあり1件" {
		t.Fatalf("notice %q", Notice(r))
	}
	if r.State["k2"].TS != "12.000000" {
		t.Fatalf("state %+v", r.State)
	}
}

func TestApplyKeepsPrevWhenOnlyParentReturned(t *testing.T) {
	// oldest は排他なので、動きが無いスレは親（古いts）だけが返る
	prev := State{"k1": msg("20.000000", "ME"), "k2": msg("9.000010", "A")}
	r, err := Apply(input(msg("10.000000", "A"), msg("9.000002", "B")), targets[:2], prev, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.New != 0 || r.State["k1"] != prev["k1"] || r.State["k2"] != prev["k2"] {
		t.Fatalf("state changed: %+v", r.State)
	}
	if !r.Entries[0].Mine {
		t.Fatal("mine must come from kept state")
	}
}

func TestApplyNewKeyIsNotNew(t *testing.T) {
	prev := State{"k1": msg("10.000000", "A"), "gone": msg("1.000000", "A")}
	r, err := Apply(input(msg("10.000000", "A"), msg("11.000000", "A")), targets[:2], prev, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.New != 0 {
		t.Fatal("new key flagged")
	}
	if _, ok := r.State["gone"]; ok {
		t.Fatal("closed target kept in state")
	}
}

func TestApplyRejectsIncompleteInput(t *testing.T) {
	cases := map[string]Input{
		"missing key": {Me: "ME", Threads: []Thread{{Key: "k1", Latest: msg("1.0", "A")}}},
		"unknown key": {Me: "ME", Threads: []Thread{{Key: "k1", Latest: msg("1.0", "A")}, {Key: "k2", Latest: msg("1.0", "A")}, {Key: "k9", Latest: msg("1.0", "A")}}},
		"no me":       {Threads: []Thread{{Key: "k1", Latest: msg("1.0", "A")}, {Key: "k2", Latest: msg("1.0", "A")}}},
		"no ts":       {Me: "ME", Threads: []Thread{{Key: "k1", Latest: Message{ByID: "A"}}, {Key: "k2", Latest: msg("1.0", "A")}}},
	}
	for name, in := range cases {
		if _, err := Apply(in, targets[:2], State{}, false); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
}

func TestParseInputRejectsBroken(t *testing.T) {
	for _, s := range []string{"{broken", `{"me":"ME"}`} {
		if _, err := ParseInput([]byte(s)); err == nil {
			t.Errorf("%q accepted", s)
		}
	}
	in, err := ParseInput([]byte(`{"me":"ME","threads":[{"key":"k1","latest":{"ts":"1.5","by_id":"A","by_name":"Aさん","text":"t"}}]}`))
	if err != nil || in.Threads[0].Latest.ByName != "Aさん" {
		t.Fatalf("%+v %v", in, err)
	}
}

func TestRender(t *testing.T) {
	loc := time.FixedZone("JST", 9*3600)
	r := Result{Entries: []Entry{
		{Target: targets[1], Latest: Message{TS: "1791429600.000000", ByName: "自分", Text: "お願いします"}, Mine: true},
		{Target: targets[0], Latest: Message{TS: "1791433200.000000", ByName: "Aさん", Text: "確認しました"}, New: true},
		{Target: targets[2], Latest: Message{TS: "1791426000.000000", ByName: "Bさん", Text: "了解"}},
	}}
	got := Render(r, time.Date(2026, 10, 8, 13, 0, 0, 0, loc))
	// 動きなしは Linear の state 順（In Progress → Waiting）。最後の発言者でボールを推測しない
	want := `# followup 2026-10-08 13:00

## 🆕 動きあり

- [Todo] NSY-1 t1 — Aさん 10/08 13:20「確認しました」 u1

## 動きなし

- [In Progress] NSY-3 t3 — Bさん 10/08 11:20「了解」 u3
- [Waiting] NSY-2 t2 — 自分 10/08 12:20「お願いします」 u2
`
	if got != want {
		t.Fatalf("got:\n%s", got)
	}
	if !strings.Contains(Render(Result{}, time.Now()), "- なし") {
		t.Fatal("empty section")
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "s")
	if err := SaveTargets(dir, targets); err != nil {
		t.Fatal(err)
	}
	got, err := LoadTargets(dir)
	if err != nil || !reflect.DeepEqual(got, targets) {
		t.Fatalf("%+v %v", got, err)
	}
	if _, first, _ := Load(dir); !first {
		t.Fatal("not first run")
	}
	r := Result{State: State{"k1": msg("1.0", "A")}, New: 2}
	if err := Save(dir, r, "md"); err != nil {
		t.Fatal(err)
	}
	st, first, err := Load(dir)
	if err != nil || first || st["k1"].TS != "1.0" {
		t.Fatalf("%+v %v %v", st, first, err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, "notice"))
	if string(b) != "動きあり2件\n" {
		t.Fatalf("notice %q", b)
	}
}

func TestExtractTargetsURLVariants(t *testing.T) {
	issues := []LinearIssue{{Identifier: "NSY-9", Description: "" +
		"https://Ex.slack.com/archives/C1/p1000000001000001 " +
		"https://x.enterprise.slack.com/archives/C2/p1000000002000002 " +
		"https://x.slack.com/archives/C3/p1000000003000009?cid=C3&amp;thread_ts=1000000003.000003"}}
	got := ExtractTargets(issues)
	var keys []string
	for _, tg := range got {
		keys = append(keys, tg.Key)
	}
	want := []string{"slack:C1/1000000001.000001", "slack:C2/1000000002.000002", "slack:C3/1000000003.000003"}
	if !reflect.DeepEqual(keys, want) {
		t.Fatalf("keys %v", keys)
	}
}

func TestApplyUnreadableThreadKeepsPrev(t *testing.T) {
	prev := State{"k1": msg("10.000000", "A")}
	in := Input{Me: "ME", Threads: []Thread{{Key: "k1", Error: true}, {Key: "k2", Error: true}}}
	r, err := Apply(in, targets[:2], prev, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.State["k1"] != prev["k1"] {
		t.Fatalf("prev lost: %+v", r.State)
	}
	if _, ok := r.State["k2"]; ok {
		t.Fatal("unread new key stored")
	}
	if !r.Entries[1].Unread {
		t.Fatalf("k2 not marked unread: %+v", r.Entries[1])
	}
	if !strings.Contains(Render(r, time.Now()), "## 読めなかった") {
		t.Fatal("unread section missing")
	}
}
