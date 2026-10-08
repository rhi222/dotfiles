package followup

// 不変条件: 🆕は「前回から変わった件」だけに付き、初回は付かない。
// 返事待ちは7日で一覧から外れる。壊れた入力は ParseInput で弾く。

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var now = time.Date(2026, 10, 8, 13, 0, 0, 0, time.UTC)

func tp(t time.Time) *time.Time { return &t }

func waiting(key string, replied bool, replyAt *time.Time) Item {
	return Item{Key: key, Kind: "waiting", Source: "slack", Where: "#ch", Who: "A",
		Summary: "q", URL: "https://example.com/" + key, Since: now.Add(-24 * time.Hour),
		Replied: replied, ReplyAt: replyAt, ReplySummary: "ok"}
}

func asked(key string, updated *time.Time) Item {
	return Item{Key: key, Kind: "asked", Source: "jira", Where: "Jira", Summary: "PROJ-123 t",
		URL: "https://example.com/" + key, Since: now.Add(-48 * time.Hour), UpdatedAt: updated}
}

func newKeys(r Result) []string {
	var ks []string
	for _, e := range r.Entries {
		if e.New {
			ks = append(ks, e.Key)
		}
	}
	return ks
}

func TestFirstRunMarksNothingNew(t *testing.T) {
	r := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", true, tp(now)), asked("a", nil)}}, State{}, true)
	if len(newKeys(r)) != 0 || Notice(r) != "" {
		t.Fatalf("first run marked new: %v", newKeys(r))
	}
	if len(r.State) != 2 {
		t.Fatalf("state not recorded: %v", r.State)
	}
}

func TestReplyArrivalIsNew(t *testing.T) {
	prev := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", false, nil)}}, State{}, true).State
	r := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", true, tp(now))}}, prev, false)
	if got := newKeys(r); len(got) != 1 || r.NewReplies != 1 {
		t.Fatalf("reply not new: %v %d", got, r.NewReplies)
	}
	again := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", true, tp(now))}}, r.State, false)
	if len(newKeys(again)) != 0 {
		t.Fatal("same reply marked new twice")
	}
}

func TestStillWaitingIsNotNew(t *testing.T) {
	prev := State{}
	r := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", false, nil)}}, prev, false)
	if len(newKeys(r)) != 0 {
		t.Fatal("unanswered waiting marked new")
	}
}

func TestAskedNewKeyAndUpdate(t *testing.T) {
	prev := Apply(Input{GeneratedAt: now, Items: []Item{asked("a", tp(now.Add(-time.Hour)))}}, State{}, true).State
	r := Apply(Input{GeneratedAt: now, Items: []Item{
		asked("a", tp(now.Add(-time.Hour))), // 変化なし
		asked("b", nil),                     // 新規
	}}, prev, false)
	if got := newKeys(r); len(got) != 1 || got[0] != "b" {
		t.Fatalf("new = %v", got)
	}
	r2 := Apply(Input{GeneratedAt: now, Items: []Item{asked("a", tp(now))}}, r.State, false)
	if got := newKeys(r2); len(got) != 1 || r2.NewAsked != 1 {
		t.Fatalf("update not new: %v", got)
	}
}

func TestWaitingOlderThan7DaysDropped(t *testing.T) {
	old := waiting("w", false, nil)
	old.Since = now.Add(-8 * 24 * time.Hour)
	r := Apply(Input{GeneratedAt: now, Items: []Item{old}}, State{}, false)
	if len(r.Entries) != 0 {
		t.Fatal("old waiting kept")
	}
}

func TestDuplicateKeysCollapsed(t *testing.T) {
	r := Apply(Input{GeneratedAt: now, Items: []Item{asked("a", nil), asked("a", nil)}}, State{}, false)
	if len(r.Entries) != 1 || r.NewAsked != 1 {
		t.Fatalf("entries=%d newAsked=%d", len(r.Entries), r.NewAsked)
	}
}

func TestRepliedWithoutReplyAtCountsOnce(t *testing.T) {
	r := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", true, nil)}}, State{}, false)
	if r.NewReplies != 1 {
		t.Fatal("first reply not new")
	}
	r2 := Apply(Input{GeneratedAt: now, Items: []Item{waiting("w", true, nil)}}, r.State, false)
	if r2.NewReplies != 0 {
		t.Fatal("reply without reply_at counted twice")
	}
}

func TestParseInputRejectsBroken(t *testing.T) {
	for _, b := range []string{`{broken`, `{"generated_at":"2026-10-08T13:00:00Z"}`,
		`{"items":[]}`, `{"generated_at":"2026-10-08T13:00:00Z","items":[{"key":"","kind":"asked"}]}`,
		`{"generated_at":"2026-10-08T13:00:00Z","items":[{"key":"k","kind":"other"}]}`} {
		if _, err := ParseInput([]byte(b)); err == nil {
			t.Errorf("accepted: %s", b)
		}
	}
	if _, err := ParseInput([]byte(`{"generated_at":"2026-10-08T13:00:00Z","items":[]}`)); err != nil {
		t.Errorf("rejected empty items: %v", err)
	}
}

func TestRenderSections(t *testing.T) {
	r := Apply(Input{GeneratedAt: now, Items: []Item{
		waiting("w1", true, tp(now)), waiting("w2", false, nil), asked("a", nil),
	}}, State{}, false)
	md := Render(r, now)
	for _, want := range []string{"## 返事が来た", "## 返事待ち", "## 頼まれ事", "🆕", "1日経過", "https://example.com/w2"} {
		if !strings.Contains(md, want) {
			t.Errorf("missing %q in:\n%s", want, md)
		}
	}
	if Notice(r) != "返事1件・頼まれ事1件" {
		t.Errorf("notice = %q", Notice(r))
	}
}

func TestSaveAndLoad(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")
	if _, first, err := Load(dir); err != nil || !first {
		t.Fatalf("missing state: first=%v err=%v", first, err)
	}
	r := Apply(Input{GeneratedAt: now, Items: []Item{asked("a", nil)}}, State{}, false)
	if err := Save(dir, r, "md"); err != nil {
		t.Fatal(err)
	}
	st, first, err := Load(dir)
	if err != nil || first || st["a"] == "" {
		t.Fatalf("reload: %v %v %v", st, first, err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "notice")); string(b) != "返事0件・頼まれ事1件\n" {
		t.Fatalf("notice = %q", b)
	}
	// 変化なしの実行は notice を消さない（cronが消費する）が、変化ありなら上書きする
	r2 := Apply(Input{GeneratedAt: now, Items: []Item{asked("a", nil), asked("b", nil), asked("c", nil)}}, st, false)
	if err := Save(dir, r2, "md"); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "notice")); string(b) != "返事0件・頼まれ事2件\n" {
		t.Fatalf("notice not overwritten: %q", b)
	}
}
