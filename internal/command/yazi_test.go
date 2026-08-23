// yazi-updateはpackage.tomlとremote HEADが同じならupgradeを実行しない。
package command

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

const (
	yaziOldSHA = "1111111111111111111111111111111111111111"
	yaziNewSHA = "2222222222222222222222222222222222222222"
)

func yaziTestEnv(t *testing.T, f *execx.Fake, rev string) Env {
	t.Helper()
	path := filepath.Join(t.TempDir(), "package.toml")
	contents := `[[plugin.deps]]
use = "yazi-rs/plugins:git"
rev = "` + rev + `"
hash = "fixture"

[[plugin.deps]]
use = "yazi-rs/plugins:smart-enter"
rev = "` + rev + `"
hash = "fixture"
`
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
	return Env{Runner: f, YaziPackageFile: path, YaziBin: "ya"}
}

func TestYaziUpdateSkipsWhenRemoteHEADMatches(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: yaziNewSHA + "\tHEAD\n"})
	env := yaziTestEnv(t, f, yaziNewSHA[:7])

	code, out, errOut := runEnv(t, env, "yazi-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "unchanged (2 packages), skipping") {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out, errOut)
	}
	if len(f.Calls) != 1 {
		t.Fatalf("同じrepositoryを複数回確認したかupgradeを呼んだ: %v", f.Calls)
	}
}

func TestYaziUpdateRunsUpgradeWhenRemoteChanged(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: yaziNewSHA + "\tHEAD\n"})
	f.On("ya", execx.Result{Stdout: "Done!\n"})
	env := yaziTestEnv(t, f, yaziOldSHA[:7])

	code, out, errOut := runEnv(t, env, "yazi-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "changes detected") {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out, errOut)
	}
	if got := f.Calls[len(f.Calls)-1].String(); got != "ya pkg upgrade" {
		t.Fatalf("call=%q", got)
	}
}

func TestYaziUpdateDoesNotHideUpgradeFailure(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: yaziNewSHA + "\tHEAD\n"})
	f.On("ya", execx.Result{ExitCode: 9, Stderr: "failed\n"})
	env := yaziTestEnv(t, f, yaziOldSHA[:7])

	code, _, errOut := runEnv(t, env, "yazi-update")
	if code != 9 || !strings.Contains(errOut, "failed") {
		t.Fatalf("code=%d stderr=%q", code, errOut)
	}
}

func TestYaziUpdateDoesNotUpgradeWhenRemoteCheckFails(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{ExitCode: 128})
	env := yaziTestEnv(t, f, yaziOldSHA[:7])

	code, _, errOut := runEnv(t, env, "yazi-update")
	if code != 1 || !strings.Contains(errOut, "remote") || len(f.Calls) != 1 {
		t.Fatalf("code=%d stderr=%q calls=%v", code, errOut, f.Calls)
	}
}

func TestYaziUpdateSkipsPinnedPackageWithoutNetwork(t *testing.T) {
	f := execx.NewFake()
	env := yaziTestEnv(t, f, "="+yaziOldSHA[:7])

	code, out, errOut := runEnv(t, env, "yazi-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "skipping") || len(f.Calls) != 0 {
		t.Fatalf("code=%d stdout=%q stderr=%q calls=%v", code, out, errOut, f.Calls)
	}
}

func TestYaziUpdateSkipsWhenPackageFileDoesNotExist(t *testing.T) {
	f := execx.NewFake()
	env := Env{Runner: f, YaziPackageFile: filepath.Join(t.TempDir(), "missing.toml"), YaziBin: "ya"}

	code, out, errOut := runEnv(t, env, "yazi-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "skipping") || len(f.Calls) != 0 {
		t.Fatalf("code=%d stdout=%q stderr=%q calls=%v", code, out, errOut, f.Calls)
	}
}
