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
	return Env{Runner: f, YaziPackageFile: path, YaziBin: "ya", YaziStateFile: filepath.Join(t.TempDir(), "state")}
}

func writeYaziPlugin(t *testing.T, env Env, body string) {
	t.Helper()
	dir := filepath.Join(filepath.Dir(env.YaziPackageFile), "plugins", "git.yazi")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "main.lua"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func setYaziRev(t *testing.T, env Env, from, to string) {
	t.Helper()
	b, err := os.ReadFile(env.YaziPackageFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(env.YaziPackageFile, []byte(strings.ReplaceAll(string(b), from, to)), 0o644); err != nil {
		t.Fatal(err)
	}
}

// 前回deploy後にpackage.tomlだけが変わった（他端末のupgradeをpullした）状態を作る。
// syncは前回deploy後の2回目のya呼び出しが返す結果。
func yaziPulledEnv(t *testing.T, f *execx.Fake, sync execx.Result) Env {
	t.Helper()
	f.On("git", execx.Result{Stdout: yaziOldSHA + "\tHEAD\n"})
	f.On("ya", execx.Result{Stdout: "Done!\n"}).On("ya", sync)
	env := yaziTestEnv(t, f, yaziNewSHA[:7])
	writeYaziPlugin(t, env, "deployed")
	if code, _, errOut := runEnv(t, env, "yazi-update"); code != 0 {
		t.Fatalf("初回deployに失敗: %s", errOut)
	}
	setYaziRev(t, env, yaziNewSHA[:7], yaziOldSHA[:7])
	f.Calls = nil
	return env
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

func TestYaziUpdateRecordsStateAfterUpgrade(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: yaziNewSHA + "\tHEAD\n"})
	f.On("ya", execx.Result{Stdout: "Done!\n"})
	env := yaziTestEnv(t, f, yaziOldSHA[:7])
	writeYaziPlugin(t, env, "deployed")

	if code, _, errOut := runEnv(t, env, "yazi-update"); code != 0 {
		t.Fatalf("code=%d stderr=%q", code, errOut)
	}
	if _, err := os.Stat(env.YaziStateFile); err != nil {
		t.Fatalf("upgrade成功後にstateを記録していない: %v", err)
	}
}

func TestYaziUpdateSyncsPristineBodyToPulledPackageFile(t *testing.T) {
	f := execx.NewFake()
	env := yaziPulledEnv(t, f, execx.Result{Stdout: "Done!\n"})

	code, out, errOut := runEnv(t, env, "yazi-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "sync") {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out, errOut)
	}
	if len(f.Calls) == 0 || f.Calls[0].String() != "ya pkg install --discard" {
		t.Fatalf("宣言に揃えていない: %v", f.Calls)
	}
}

func TestYaziUpdateDoesNotDiscardLocallyEditedBody(t *testing.T) {
	f := execx.NewFake()
	env := yaziPulledEnv(t, f, execx.Result{Stdout: "Done!\n"})
	writeYaziPlugin(t, env, "edited by hand")

	_, _, errOut := runEnv(t, env, "yazi-update")
	for _, c := range f.Calls {
		if strings.Contains(c.String(), "--discard") {
			t.Fatalf("手元の編集を捨てた: %v", f.Calls)
		}
	}
	if !strings.Contains(errOut, "変更") {
		t.Fatalf("手元の編集を警告していない: stderr=%q", errOut)
	}
}

func TestYaziUpdateDoesNotSyncWithoutState(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: yaziNewSHA + "\tHEAD\n"})
	env := yaziTestEnv(t, f, yaziNewSHA[:7])
	writeYaziPlugin(t, env, "unknown origin")

	runEnv(t, env, "yazi-update")
	for _, c := range f.Calls {
		if strings.Contains(c.String(), "--discard") {
			t.Fatalf("記録の無い中身を捨てた: %v", f.Calls)
		}
	}
}

func TestYaziUpdateStopsWhenSyncFails(t *testing.T) {
	f := execx.NewFake()
	env := yaziPulledEnv(t, f, execx.Result{ExitCode: 3, Stderr: "sync failed\n"})

	code, _, errOut := runEnv(t, env, "yazi-update")
	if code == 0 || !strings.Contains(errOut, "sync failed") {
		t.Fatalf("code=%d stderr=%q", code, errOut)
	}
	if len(f.Calls) != 1 {
		t.Fatalf("sync失敗後も続行した: %v", f.Calls)
	}
}
