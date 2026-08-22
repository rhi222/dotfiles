// fisher-updateはremote SHAが変わった場合だけfull reconcileし、成功時だけcacheを進める。
package command

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

const (
	fisherSHA = "1111111111111111111111111111111111111111"
	fzfSHA    = "2222222222222222222222222222222222222222"
	tideTag   = "3333333333333333333333333333333333333333"
	tideSHA   = "4444444444444444444444444444444444444444"
)

func fisherTestEnv(t *testing.T, f *execx.Fake) Env {
	t.Helper()
	dir := t.TempDir()
	plugins := filepath.Join(dir, "fish_plugins")
	if err := os.WriteFile(plugins, []byte("jorgebucaran/fisher\npatrickf1/fzf.fish\nilancosman/tide@v6\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return Env{Runner: f, FisherPluginFile: plugins, FisherCacheFile: filepath.Join(dir, "cache", "refs")}
}

func addFisherRefs(f *execx.Fake, fzf string) {
	f.On("git", execx.Result{Stdout: fisherSHA + "\tHEAD\n"})
	f.On("git", execx.Result{Stdout: fzf + "\tHEAD\n"})
	f.On("git", execx.Result{Stdout: tideTag + "\trefs/tags/v6\n" + tideSHA + "\trefs/tags/v6^{}\n"})
}

func TestFisherUpdateCachesSuccessfulRemoteState(t *testing.T) {
	f := execx.NewFake()
	addFisherRefs(f, fzfSHA)
	f.On("fish", execx.Result{Stdout: "Updated 3 plugin/s\n"})
	env := fisherTestEnv(t, f)

	code, out, errOut := runEnv(t, env, "fisher-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "full reconcile") {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out, errOut)
	}
	cache, err := os.ReadFile(env.FisherCacheFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(cache), "ilancosman/tide@v6\t"+tideSHA) {
		t.Fatalf("annotated tagの実commitが無い: %q", cache)
	}
}

func TestFisherUpdateSkipsWhenRemoteStateMatches(t *testing.T) {
	initial := execx.NewFake()
	addFisherRefs(initial, fzfSHA)
	initial.On("fish", execx.Result{})
	env := fisherTestEnv(t, initial)
	if code, _, _ := runEnv(t, env, "fisher-update"); code != 0 {
		t.Fatalf("initial code=%d", code)
	}

	second := execx.NewFake()
	addFisherRefs(second, fzfSHA)
	env.Runner = second
	code, out, errOut := runEnv(t, env, "fisher-update")
	if code != 0 || errOut != "" || !strings.Contains(out, "unchanged (3 plugins), skipping") {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out, errOut)
	}
	if len(second.Calls) != 3 {
		t.Fatalf("Fisherを呼んだ: %v", second.Calls)
	}
}

func TestFisherFailureDoesNotAdvanceCache(t *testing.T) {
	initial := execx.NewFake()
	addFisherRefs(initial, fzfSHA)
	initial.On("fish", execx.Result{})
	env := fisherTestEnv(t, initial)
	runEnv(t, env, "fisher-update")
	before, _ := os.ReadFile(env.FisherCacheFile)

	failed := execx.NewFake()
	addFisherRefs(failed, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	failed.On("fish", execx.Result{ExitCode: 9, Stderr: "failed\n"})
	env.Runner = failed
	code, _, _ := runEnv(t, env, "fisher-update")
	after, _ := os.ReadFile(env.FisherCacheFile)
	if code != 9 || string(after) != string(before) {
		t.Fatalf("code=%d cache changed=%v", code, string(after) != string(before))
	}
}

func TestFisherRemoteFailureDoesNotRunFisher(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{ExitCode: 128})
	env := fisherTestEnv(t, f)
	code, _, errOut := runEnv(t, env, "fisher-update")
	if code != 1 || !strings.Contains(errOut, "remote") || len(f.Calls) != 1 {
		t.Fatalf("code=%d stderr=%q calls=%v", code, errOut, f.Calls)
	}
}

func TestFisherUnsupportedPluginInvalidatesOldCache(t *testing.T) {
	f := execx.NewFake()
	f.On("fish", execx.Result{})
	env := fisherTestEnv(t, f)
	if err := os.WriteFile(env.FisherPluginFile, []byte("/tmp/local-plugin\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(env.FisherCacheFile), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(env.FisherCacheFile, []byte("stale"), 0o644)

	code, _, _ := runEnv(t, env, "fisher-update")
	if code != 0 {
		t.Fatalf("code=%d", code)
	}
	if _, err := os.Stat(env.FisherCacheFile); !os.IsNotExist(err) {
		t.Fatalf("古いcacheが残った: %v", err)
	}
}
