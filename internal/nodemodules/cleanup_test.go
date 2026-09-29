// node_modules cleanupはdry-run既定で、commitもinstallも古いnode_modulesだけを候補にする。
// git管理外や最近installしたものは消さず、pnpmのstoreは削除後にpnpm自身に掃除させる。
package nodemodules

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rhi222/dotfiles/internal/execx"
)

var now = time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)

func daysAgo(n int) time.Time { return now.AddDate(0, 0, -n) }

func TestIsStale(t *testing.T) {
	tests := []struct {
		name      string
		head      time.Time
		installed time.Time
		want      bool
	}{
		{"commitもinstallも古い", daysAgo(200), daysAgo(200), true},
		// **commitが古くてもinstallが新しければ使っている。** 参照だけのrepoを消さない
		{"installが新しい", daysAgo(200), daysAgo(3), false},
		{"commitが新しい", daysAgo(3), daysAgo(200), false},
		{"ちょうど閾値は残す", daysAgo(90), daysAgo(90), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsStale(now, 90, tt.head, tt.installed); got != tt.want {
				t.Errorf("IsStale = %v, want %v", got, tt.want)
			}
		})
	}
}

// fixture は root 配下に repo/node_modules を作り、HEAD の時刻表を返す。
type fixture struct {
	root  string
	heads map[string]time.Time // repo dir → HEAD commit 時刻。無ければ git 管理外
}

func newFixture(t *testing.T) *fixture {
	return &fixture{root: t.TempDir(), heads: map[string]time.Time{}}
}

// add は rel/node_modules を installed 時刻で作る。head がゼロなら git 管理外。
func (f *fixture) add(t *testing.T, rel string, head, installed time.Time, marker string) string {
	t.Helper()
	repo := filepath.Join(f.root, rel)
	nm := filepath.Join(repo, "node_modules")
	if err := os.MkdirAll(filepath.Join(nm, "pkg"), 0o755); err != nil {
		t.Fatal(err)
	}
	if marker != "" {
		if err := os.WriteFile(filepath.Join(nm, marker), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(filepath.Join(nm, marker), installed, installed); err != nil {
			t.Fatal(err)
		}
	}
	for _, p := range []string{filepath.Join(nm, "pkg"), nm} {
		if err := os.Chtimes(p, installed, installed); err != nil {
			t.Fatal(err)
		}
	}
	if !head.IsZero() {
		f.heads[repo] = head
	}
	return nm
}

func (f *fixture) headTime(_ context.Context, dir string) (time.Time, bool) {
	for d := dir; d != filepath.Dir(d); d = filepath.Dir(d) {
		if h, ok := f.heads[d]; ok {
			return h, true
		}
	}
	return time.Time{}, false
}

func fakeRunner() *execx.Fake {
	f := execx.NewFake()
	for i := 0; i < 40; i++ {
		f.On("du", execx.Result{Stdout: "2048\t/p\n"})
		f.On("pnpm", execx.Result{})
	}
	return f
}

func (f *fixture) run(t *testing.T, r execx.Runner, execute bool) string {
	t.Helper()
	var out bytes.Buffer
	Run(context.Background(), r, Config{
		Roots:    []string{f.root},
		Days:     90,
		Now:      now,
		Execute:  execute,
		HeadTime: f.headTime,
	}, IO{Stdout: &out, Stderr: &out})
	return out.String()
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func TestRunDryRunListsStaleOnly(t *testing.T) {
	f := newFixture(t)
	stale := f.add(t, "old", daysAgo(200), daysAgo(200), ".package-lock.json")
	fresh := f.add(t, "new", daysAgo(3), daysAgo(3), ".package-lock.json")

	out := f.run(t, fakeRunner(), false)

	if !strings.Contains(out, "DRY-RUN") {
		t.Errorf("モード表示が無い: %q", out)
	}
	if !strings.Contains(out, stale) {
		t.Errorf("古い node_modules を候補に出していない: %q", out)
	}
	if strings.Contains(out, fresh) {
		t.Errorf("新しい node_modules を候補に出した: %q", out)
	}
	// daily-update が件数とサイズを拾う契約行
	if !strings.Contains(out, "node-modules-cleanup: CANDIDATES=1 SIZE_MB=2\n") {
		t.Errorf("契約行が無い: %q", out)
	}
	if !exists(stale) {
		t.Error("dry-run なのに削除した")
	}
	if !strings.Contains(out, "--execute") {
		t.Errorf("実行方法を案内していない: %q", out)
	}
}

func TestRunExecuteDeletesStaleOnly(t *testing.T) {
	f := newFixture(t)
	stale := f.add(t, "old", daysAgo(200), daysAgo(200), ".package-lock.json")
	fresh := f.add(t, "new", daysAgo(3), daysAgo(3), ".package-lock.json")
	// **installが新しければ、commitが古くても消さない**
	reinstalled := f.add(t, "reinstalled", daysAgo(200), daysAgo(1), ".package-lock.json")

	out := f.run(t, fakeRunner(), true)

	if !strings.Contains(out, "EXECUTE") {
		t.Errorf("モード表示が無い: %q", out)
	}
	if exists(stale) {
		t.Error("古い node_modules を消していない")
	}
	for _, p := range []string{fresh, reinstalled} {
		if !exists(p) {
			t.Errorf("使っている node_modules を消した: %s", p)
		}
	}
	if !exists(filepath.Join(f.root, "old", "")) {
		t.Error("repo 本体まで消した")
	}
}

func TestRunUsesInstallMarkerTime(t *testing.T) {
	// dir の mtime はトップレベルの増減でしか変わらない。install 時に書き直される
	// marker の時刻を見ないと、再 install したばかりのものを古いと誤判定する
	f := newFixture(t)
	nm := f.add(t, "repo", daysAgo(200), daysAgo(200), ".modules.yaml")
	if err := os.Chtimes(filepath.Join(nm, ".modules.yaml"), daysAgo(1), daysAgo(1)); err != nil {
		t.Fatal(err)
	}

	out := f.run(t, fakeRunner(), true)

	if !exists(nm) {
		t.Errorf("marker が新しいのに消した: %q", out)
	}
}

func TestRunKeepsNonGit(t *testing.T) {
	// **git 管理外は古さを判定できないので消さない。** 存在だけ知らせる
	f := newFixture(t)
	nm := f.add(t, "nogit", time.Time{}, daysAgo(400), "")

	out := f.run(t, fakeRunner(), true)

	if !exists(nm) {
		t.Error("git 管理外の node_modules を消した")
	}
	if !strings.Contains(out, "[SKIP]") || !strings.Contains(out, nm) {
		t.Errorf("skip したことを出していない: %q", out)
	}
	if !strings.Contains(out, "CANDIDATES=0") {
		t.Errorf("git 管理外を候補に数えた: %q", out)
	}
}

func TestRunDoesNotDescendIntoNodeModules(t *testing.T) {
	// node_modules の中の node_modules は親ごと消えるので別候補にしない
	f := newFixture(t)
	nm := f.add(t, "repo", daysAgo(200), daysAgo(200), ".package-lock.json")
	if err := os.MkdirAll(filepath.Join(nm, "pkg", "node_modules"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{filepath.Join(nm, "pkg"), nm} {
		if err := os.Chtimes(p, daysAgo(200), daysAgo(200)); err != nil {
			t.Fatal(err)
		}
	}

	out := f.run(t, fakeRunner(), false)

	if !strings.Contains(out, "CANDIDATES=1") {
		t.Errorf("入れ子を別候補に数えた: %q", out)
	}
}

func TestRunPrunesPnpmStoreAfterDeletingPnpmModules(t *testing.T) {
	// pnpm の node_modules は store への hardlink。消しただけでは容量が戻らない
	f := newFixture(t)
	f.add(t, "repo", daysAgo(200), daysAgo(200), ".modules.yaml")
	r := fakeRunner()

	f.run(t, r, true)

	if !called(r, "pnpm", "store prune") {
		t.Errorf("pnpm store prune を呼んでいない: %v", r.Calls)
	}
}

func TestRunDoesNotPrunePnpmStoreOnDryRun(t *testing.T) {
	f := newFixture(t)
	f.add(t, "repo", daysAgo(200), daysAgo(200), ".modules.yaml")
	r := fakeRunner()

	f.run(t, r, false)

	if called(r, "pnpm", "store prune") {
		t.Error("dry-run なのに pnpm store prune を呼んだ")
	}
}

func TestRunDoesNotPrunePnpmStoreForNpmOnly(t *testing.T) {
	f := newFixture(t)
	f.add(t, "repo", daysAgo(200), daysAgo(200), ".package-lock.json")
	r := fakeRunner()

	f.run(t, r, true)

	if called(r, "pnpm", "store prune") {
		t.Error("pnpm の node_modules を消していないのに store prune を呼んだ")
	}
}

func called(f *execx.Fake, name, args string) bool {
	for _, c := range f.Calls {
		if c.Name == name && strings.Join(c.Args, " ") == args {
			return true
		}
	}
	return false
}
