// rebuild はカレントディレクトリに依存せず、ビルド元repositoryの既存setupを使う。
// setup側のテスト・atomic置換を迂回せず、終了コードと出力をそのまま利用者へ返す。
package command

import (
	"errors"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

func TestRebuildRunsSetupFromEmbeddedRepo(t *testing.T) {
	f := execx.NewFake()
	f.On("bash", execx.Result{Stdout: "setup ok\n"})

	code, out, errOut := runEnv(t, Env{Runner: f, Repo: "/data/dotfiles", Cwd: "/elsewhere"},
		"rebuild")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "setup ok") || errOut != "" {
		t.Errorf("stdout=%q stderr=%q", out, errOut)
	}
	if len(f.Calls) != 1 {
		t.Fatalf("calls = %v, want 1", f.Calls)
	}
	call := f.Calls[0]
	if got, want := call.String(), "bash /data/dotfiles/scripts/setup/dotctl.sh"; got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
	if call.Dir != "/data/dotfiles" {
		t.Errorf("dir = %q, want repository", call.Dir)
	}
}

func TestRebuildForwardsSkipTests(t *testing.T) {
	f := execx.NewFake()
	f.On("bash", execx.Result{})

	code, _, _ := runEnv(t, Env{Runner: f, Repo: "/repo"}, "rebuild", "--skip-tests")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if got, want := f.Calls[0].String(), "bash /repo/scripts/setup/dotctl.sh --skip-tests"; got != want {
		t.Errorf("command = %q, want %q", got, want)
	}
}

func TestRebuildReturnsSetupFailure(t *testing.T) {
	f := execx.NewFake()
	f.On("bash", execx.Result{Stderr: "build failed\n", ExitCode: 9})

	code, _, errOut := runEnv(t, Env{Runner: f, Repo: "/repo"}, "rebuild")
	if code != 9 {
		t.Errorf("exit = %d, want 9", code)
	}
	if !strings.Contains(errOut, "build failed") {
		t.Errorf("setup の stderr を返していない: %q", errOut)
	}
}

func TestRebuildReportsRunnerFailure(t *testing.T) {
	f := execx.NewFake()
	f.OnError("bash", errors.New("not found"))

	code, _, errOut := runEnv(t, Env{Runner: f, Repo: "/repo"}, "rebuild")
	if code != 1 || !strings.Contains(errOut, "not found") {
		t.Errorf("exit=%d stderr=%q", code, errOut)
	}
}

func TestRebuildRequiresRepo(t *testing.T) {
	f := execx.NewFake()
	code, _, errOut := runEnv(t, Env{Runner: f}, "rebuild")
	if code != 1 || !strings.Contains(errOut, "DOTCTL_REPO") {
		t.Errorf("exit=%d stderr=%q", code, errOut)
	}
	if len(f.Calls) != 0 {
		t.Errorf("repo不明で外部commandを呼んだ: %v", f.Calls)
	}
}

func TestRebuildRejectsUnknownFlag(t *testing.T) {
	f := execx.NewFake()
	code, _, errOut := runEnv(t, Env{Runner: f, Repo: "/repo"}, "rebuild", "--force")
	if code != 2 || !strings.Contains(errOut, "--force") {
		t.Errorf("exit=%d stderr=%q", code, errOut)
	}
	if len(f.Calls) != 0 {
		t.Errorf("不明な引数で外部commandを呼んだ: %v", f.Calls)
	}
}

func TestRebuildDoesNotWarnAboutTheSkewItFixes(t *testing.T) {
	f := execx.NewFake()
	f.On("bash", execx.Result{})

	code, _, errOut := runEnv(t, Env{
		Runner: f, Repo: "/repo", Commit: "old-commit",
	}, "rebuild")
	if code != 0 || errOut != "" {
		t.Errorf("exit=%d stderr=%q", code, errOut)
	}
	if len(f.Calls) != 1 || f.Calls[0].Name != "bash" {
		t.Errorf("rebuild前にskew検査を呼んだ: %v", f.Calls)
	}
}
