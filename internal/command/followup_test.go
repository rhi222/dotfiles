package command

// 不変条件: dotctl followup apply は入力が targets.json と揃っているときだけ状態を書く。
// 欠けた入力では state.json を作らず exit 1。

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const linearIssues = `[{"identifier":"NSY-1","title":"t","url":"https://linear.example/1",
"description":"https://example.slack.com/archives/C1/p1788425240728449"}]`

const followupInput = `{"me":"ME","threads":[{"key":"slack:C1/1788425240.728449",
"latest":{"ts":"1788425464.592589","by_id":"A","by_name":"Aさん","text":"t"}}]}`

func followupEnv(t *testing.T, stdin string, dir string) (Env, *bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	var out, errb bytes.Buffer
	return Env{Stdout: &out, Stderr: &errb, Stdin: strings.NewReader(stdin), FollowupStateDir: dir}, &out, &errb
}

func runTargets(t *testing.T, dir string) string {
	t.Helper()
	env, out, errb := followupEnv(t, linearIssues, dir)
	if code := Run(context.Background(), []string{"followup", "targets", "--in", "-"}, env); code != 0 {
		t.Fatalf("targets exit=%d stderr=%s", code, errb)
	}
	return out.String()
}

func TestFollowupTargets(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "followup")
	out := runTargets(t, dir)
	if !strings.Contains(out, `"oldest":"1788425240.728449"`) || !strings.Contains(out, `"channel":"C1"`) {
		t.Fatalf("stdout = %s", out)
	}
	if _, err := os.Stat(filepath.Join(dir, "targets.json")); err != nil {
		t.Fatal(err)
	}
}

func TestFollowupApplyStdin(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "followup")
	runTargets(t, dir)
	env, out, errb := followupEnv(t, followupInput, dir)
	if code := Run(context.Background(), []string{"followup", "apply", "--in", "-"}, env); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, errb)
	}
	if !strings.Contains(out.String(), filepath.Join(dir, "latest.md")) {
		t.Fatalf("stdout = %q", out)
	}
	if _, err := os.Stat(filepath.Join(dir, "notice")); err == nil {
		t.Error("notice written on first run")
	}
}

func TestFollowupApplyWithoutTargetsFails(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "followup")
	env, _, _ := followupEnv(t, followupInput, dir)
	if code := Run(context.Background(), []string{"followup", "apply", "--in", "-"}, env); code != 1 {
		t.Fatalf("exit=%d, want 1", code)
	}
}

func TestFollowupApplyIncompleteWritesNothing(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "followup")
	runTargets(t, dir)
	env, _, _ := followupEnv(t, `{"me":"ME","threads":[]}`, dir)
	if code := Run(context.Background(), []string{"followup", "apply", "--in", "-"}, env); code != 1 {
		t.Fatalf("exit=%d, want 1", code)
	}
	if _, err := os.Stat(filepath.Join(dir, "state.json")); err == nil {
		t.Fatal("state written on incomplete input")
	}
}

func TestFollowupUsage(t *testing.T) {
	env, _, _ := followupEnv(t, "", t.TempDir())
	for _, args := range [][]string{{"followup"}, {"followup", "apply"}, {"followup", "targets"}} {
		if code := Run(context.Background(), args, env); code != 2 {
			t.Errorf("%v exit=%d, want 2", args, code)
		}
	}
}

func TestFollowupTargetsRejectsNull(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "followup")
	env, _, _ := followupEnv(t, "null", dir)
	if code := Run(context.Background(), []string{"followup", "targets", "--in", "-"}, env); code != 1 {
		t.Fatalf("exit=%d, want 1", code)
	}
	if _, err := os.Stat(filepath.Join(dir, "targets.json")); err == nil {
		t.Fatal("targets.json written for null")
	}
}
