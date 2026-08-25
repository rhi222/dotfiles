package session

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeTestMarker(t *testing.T, dir, name string, marker Marker) string {
	t.Helper()
	b, err := json.Marshal(marker)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, b, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func testPaneJSON(panes ...Pane) []byte {
	v := paneList{}
	v.Result.Panes = panes
	b, _ := json.Marshal(v)
	return b
}

func TestBuildPlanMapsMovedPaneByUniqueCwdAndKeepsOldSessionTag(t *testing.T) {
	dir := t.TempDir()
	writeTestMarker(t, dir, "owner.json", Marker{
		Version: 2, Owner: "owner", PaneID: "w1:p1", SocketPath: "/sock",
		Cwd: "/repo", Kind: "session", SessionTag: "w1:p1",
	})
	plan, err := BuildPlan(PlanOptions{MarkerDir: dir, SocketPath: "/sock", FocusedWorkspace: "w2",
		PaneJSON: testPaneJSON(Pane{PaneID: "w2:p9", WorkspaceID: "w2", Cwd: "/repo"})})
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Entries) != 1 {
		t.Fatalf("entries=%#v", plan.Entries)
	}
	if got, want := plan.Entries[0].Command, "env HERDR_RESTORE_SESSION_TAG='w1:p1' nvim"; got != want {
		t.Fatalf("command=%q want %q", got, want)
	}
}

func TestBuildPlanRefusesAmbiguousCwd(t *testing.T) {
	dir := t.TempDir()
	path := writeTestMarker(t, dir, "owner.json", Marker{Version: 2, Owner: "owner", PaneID: "gone", SocketPath: "/sock", Cwd: "/repo", Kind: "session"})
	plan, err := BuildPlan(PlanOptions{MarkerDir: dir, SocketPath: "/sock", PaneJSON: testPaneJSON(
		Pane{PaneID: "w1:p1", Cwd: "/repo"}, Pane{PaneID: "w1:p2", Cwd: "/repo"})})
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Entries) != 0 || len(plan.Stale) != 0 {
		t.Fatalf("plan=%#v", plan)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatal("ambiguous marker should be retained")
	}
}

func TestBuildPlanUsesNewestOwnerAndQuotesFileArgs(t *testing.T) {
	dir := t.TempDir()
	old := writeTestMarker(t, dir, "old.json", Marker{Version: 2, Owner: "old", PaneID: "w1:p1", SocketPath: "/sock", Cwd: "/repo", Kind: "session"})
	if err := os.Chtimes(old, time.Unix(1, 0), time.Unix(1, 0)); err != nil {
		t.Fatal(err)
	}
	writeTestMarker(t, dir, "new.json", Marker{Version: 2, Owner: "new", PaneID: "w1:p1", SocketPath: "/sock", Cwd: "/repo", Kind: "files", Args: []string{"a b", "it's.txt"}})
	plan, err := BuildPlan(PlanOptions{MarkerDir: dir, SocketPath: "/sock", PaneJSON: testPaneJSON(Pane{PaneID: "w1:p1", Cwd: "/repo"})})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := plan.Entries[0].Command, "nvim -- 'a b' 'it'\"'\"'s.txt'"; got != want {
		t.Fatalf("command=%q want %q", got, want)
	}
}

func TestBuildPlanFiltersSessionAndMarksUnmatchedStale(t *testing.T) {
	dir := t.TempDir()
	other := writeTestMarker(t, dir, "other.json", Marker{Version: 2, Owner: "other", PaneID: "w1:p1", SocketPath: "/other", Cwd: "/x", Kind: "session"})
	stale := writeTestMarker(t, dir, "stale.json", Marker{Version: 2, Owner: "stale", PaneID: "gone", SocketPath: "/sock", Cwd: "/missing", Kind: "session"})
	plan, err := BuildPlan(PlanOptions{MarkerDir: dir, SocketPath: "/sock", PaneJSON: testPaneJSON(Pane{PaneID: "w1:p1", Cwd: "/repo"})})
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Entries) != 0 || len(plan.Stale) != 1 || plan.Stale[0] != stale {
		t.Fatalf("plan=%#v", plan)
	}
	if _, err := os.Stat(other); err != nil {
		t.Fatal("other session marker must be untouched")
	}
}

func TestBuildPlanLegacyOnlyWhenAllowed(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "w1:p1"), []byte("/repo\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	opts := PlanOptions{MarkerDir: dir, SocketPath: "/sock", PaneJSON: testPaneJSON(Pane{PaneID: "w1:p1", Cwd: "/repo"})}
	plan, err := BuildPlan(opts)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Entries) != 0 {
		t.Fatal("legacy marker accepted without opt-in")
	}
	opts.AllowLegacy = true
	plan, err = BuildPlan(opts)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Entries) != 1 {
		t.Fatalf("entries=%#v", plan.Entries)
	}
}
