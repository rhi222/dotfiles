package command

// 不変条件: dotctl followup apply は入力が正しいときだけ状態を書く。
// 壊れた入力では状態ディレクトリに何も作らず exit 1。

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const followupInput = `{"generated_at":"2026-10-08T13:00:00Z","items":[
{"key":"jira:PROJ-1","kind":"asked","source":"jira","where":"Jira","summary":"PROJ-1 t","url":"https://example.com/1","since":"2026-10-07T13:00:00Z"}]}`

func followupEnv(t *testing.T, stdin string) (Env, *bytes.Buffer, *bytes.Buffer, string) {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "followup")
	var out, errb bytes.Buffer
	return Env{Stdout: &out, Stderr: &errb, Stdin: strings.NewReader(stdin), FollowupStateDir: dir}, &out, &errb, dir
}

func TestFollowupApplyStdin(t *testing.T) {
	env, out, errb, dir := followupEnv(t, followupInput)
	if code := Run(context.Background(), []string{"followup", "apply", "--in", "-"}, env); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, errb)
	}
	if !strings.Contains(out.String(), filepath.Join(dir, "latest.md")) {
		t.Fatalf("stdout = %q", out)
	}
	for _, f := range []string{"state.json", "latest.md"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Errorf("%s not written: %v", f, err)
		}
	}
	// 初回なので notice は無い
	if _, err := os.Stat(filepath.Join(dir, "notice")); err == nil {
		t.Error("notice written on first run")
	}
}

func TestFollowupApplyFile(t *testing.T) {
	env, _, errb, dir := followupEnv(t, "")
	in := filepath.Join(t.TempDir(), "in.json")
	if err := os.WriteFile(in, []byte(followupInput), 0o600); err != nil {
		t.Fatal(err)
	}
	if code := Run(context.Background(), []string{"followup", "apply", "--in", in}, env); code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, errb)
	}
	if _, err := os.Stat(filepath.Join(dir, "state.json")); err != nil {
		t.Fatal(err)
	}
}

func TestFollowupApplyBrokenWritesNothing(t *testing.T) {
	env, _, _, dir := followupEnv(t, "{broken")
	if code := Run(context.Background(), []string{"followup", "apply", "--in", "-"}, env); code != 1 {
		t.Fatalf("exit=%d, want 1", code)
	}
	if _, err := os.Stat(dir); err == nil {
		t.Fatal("state dir created on broken input")
	}
}

func TestFollowupApplyUsage(t *testing.T) {
	env, _, _, _ := followupEnv(t, "")
	if code := Run(context.Background(), []string{"followup", "apply"}, env); code != 2 {
		t.Fatalf("exit=%d, want 2", code)
	}
}
