// worktree cleanupは計画でDELETEになった対象だけを削除し、KEEP/SKIPには触れない。
// 個別削除の失敗後も続行し、pruneと失敗結果を呼び出し側へ返す。
package worktree

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

func TestDiscoverReposFindsGitDirsAndSkipsNested(t *testing.T) {
	root := t.TempDir()
	// root/a/.git（リポジトリ）と、その中の worktree（root/a/.wt/x/.git はファイル）
	mustMkdir(t, filepath.Join(root, "a", ".git"))
	mustMkdir(t, filepath.Join(root, "b", "c", ".git"))
	mustMkdir(t, filepath.Join(root, "plain")) // .git を持たない

	got := discoverRepos([]string{root})

	if !contains(got, filepath.Join(root, "a")) {
		t.Errorf("root/a を見つけていない: %v", got)
	}
	if !contains(got, filepath.Join(root, "b", "c")) {
		t.Errorf("入れ子のリポジトリを見つけていない: %v", got)
	}
	if contains(got, filepath.Join(root, "plain")) {
		t.Errorf(".git を持たないディレクトリを含めている: %v", got)
	}
}

func TestDiscoverReposFindsNestedReposLikeFindPrune(t *testing.T) {
	// **Shell 版と同じ挙動にする。** `find -name .git -prune` は .git 自身への
	// 降下だけを止めるので、リポジトリの内側にある別リポジトリ（submodule や
	// vendor）も拾う。拾っても git worktree list を1回余分に呼ぶだけで害は無い。
	//
	// 移植では挙動を変えない（改善は別コミットで行う）。ここを「掘らない」に
	// 変えると、submodule の worktree が検出対象から静かに外れる。
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "a", ".git"))
	mustMkdir(t, filepath.Join(root, "a", "vendor", "dep", ".git"))

	got := discoverRepos([]string{root})
	if !contains(got, filepath.Join(root, "a", "vendor", "dep")) {
		t.Errorf("入れ子のリポジトリを拾えていない: %v", got)
	}
}

func TestDiscoverReposDoesNotDescendIntoGitDir(t *testing.T) {
	// .git の内側は掘らない（.git/modules/<name>/.git を拾わない）
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "a", ".git", "modules", "m", ".git"))

	got := discoverRepos([]string{root})
	for _, g := range got {
		if strings.Contains(g, ".git") {
			t.Errorf(".git の内側を掘っている: %v", got)
		}
	}
}

func TestDiscoverReposRespectsMaxDepth(t *testing.T) {
	// 深すぎるものは拾わない（Shell 版の -maxdepth 4 と同じ）
	root := t.TempDir()
	mustMkdir(t, filepath.Join(root, "a", "b", "c", "d", "e", ".git"))

	if got := discoverRepos([]string{root}); len(got) != 0 {
		t.Errorf("maxdepth を超えたものを拾っている: %v", got)
	}
}

func TestDiscoverReposIgnoresMissingRoot(t *testing.T) {
	if got := discoverRepos([]string{"/definitely/not/here"}); len(got) != 0 {
		t.Errorf("存在しないルートで %v を返した", got)
	}
}

// --- Plan の組み立て ---

func TestBuildPlanGathersObservationsAndClassifies(t *testing.T) {
	f := execx.NewFake()
	// main worktree の解決
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	// worktree list
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n" +
		"worktree /repo/.wt/done\nbranch refs/heads/done\n\n"})
	// status --untracked-files=no（追跡変更なし）
	f.On("git", execx.Result{Stdout: ""})
	// status --untracked-files=normal（未追跡なし）
	f.On("git", execx.Result{Stdout: ""})
	// PR 状態
	f.On("gh", execx.Result{Stdout: "MERGED #5\n"})

	p := BuildPlan(context.Background(), f, Config{Roots: "/data", Repos: []string{"/repo"}})

	if len(p.Repos) != 1 || len(p.Repos[0].Items) != 1 {
		t.Fatalf("Plan = %+v", p)
	}
	it := p.Repos[0].Items[0]
	if it.Decision.Verdict != DELETE || it.Decision.Reason != "MERGED #5" {
		t.Errorf("判定 = %v / %q", it.Decision.Verdict, it.Decision.Reason)
	}
}

func TestBuildPlanSkipsPRLookupForLockedAndDetached(t *testing.T) {
	// **locked と detached では gh を呼ばない。** 判定に使わない情報のために
	// ネットワークへ出るのは無駄で、gh 未認証の端末で無意味に遅くなる
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n" +
		"worktree /repo/.wt/l\nbranch refs/heads/l\nlocked busy\n\n" +
		"worktree /repo/.wt/d\ndetached\n\n"})

	p := BuildPlan(context.Background(), f, Config{Roots: "/d", Repos: []string{"/repo"}})

	for _, c := range f.Calls {
		if c.Name == "gh" {
			t.Error("locked/detached だけなのに gh を呼んでいる")
		}
	}
	if len(p.Repos[0].Items) != 2 {
		t.Fatalf("Items = %+v", p.Repos[0].Items)
	}
	if p.Repos[0].Items[0].Decision.SkipKind != SkipLocked {
		t.Errorf("1件目 = %+v", p.Repos[0].Items[0].Decision)
	}
	if p.Repos[0].Items[1].Decision.SkipKind != SkipDetached {
		t.Errorf("2件目 = %+v", p.Repos[0].Items[1].Decision)
	}
}

func TestBuildPlanSkipsRepoWhenListingFails(t *testing.T) {
	// **1リポジトリの失敗で全体を止めない**（Shell 版が set -e を使わない理由）
	f := execx.NewFake()
	f.On("git", execx.Result{ExitCode: 128, Stderr: "not a git repository"})
	p := BuildPlan(context.Background(), f, Config{Roots: "/d", Repos: []string{"/broken", "/ok"}})
	if p == nil {
		t.Fatal("nil を返してはいけない")
	}
}

func TestBuildPlanMeasuresSizeOnlyForDeleteCandidates(t *testing.T) {
	// **測定対象は DELETE 候補だけ。** du は遅いので、消さないものは測らない
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n" +
		"worktree /repo/.wt/done\nbranch refs/heads/done\n\n" +
		"worktree /repo/.wt/open\nbranch refs/heads/open\n\n"})
	f.On("git", execx.Result{Stdout: ""}) // done: tracked
	f.On("git", execx.Result{Stdout: ""}) // done: untracked
	f.On("gh", execx.Result{Stdout: "MERGED #1\n"})
	f.On("git", execx.Result{Stdout: ""}) // open: tracked
	f.On("git", execx.Result{Stdout: ""}) // open: untracked
	f.On("gh", execx.Result{Stdout: "OPEN #2\n"})
	f.On("du", execx.Result{Stdout: "2048\t/repo/.wt/done\n"})

	p := BuildPlan(context.Background(), f, Config{Roots: "/d", Repos: []string{"/repo"}, ShowSize: true})

	du := 0
	for _, c := range f.Calls {
		if c.Name == "du" {
			du++
		}
	}
	if du != 1 {
		t.Errorf("du の呼び出し = %d 回, want 1（DELETE 候補だけ）", du)
	}
	if p.FreedKB != 2048 {
		t.Errorf("FreedKB = %d, want 2048", p.FreedKB)
	}
}

// --- 実行 ---

func TestExecuteRemovesWithForceAlways(t *testing.T) {
	// **DELETE 候補は常に --force で remove する。** git worktree remove は
	// 未追跡ファイルが1つでもあると --force なしで exit 128 で拒否するので、
	// 未追跡のみの MERGED を既定モードで消せるようにするには常に要る。
	// 安全性は Classify が担保している。
	f := execx.NewFake()
	f.On("git", execx.Result{})
	p := &Plan{Repos: []RepoPlan{{Repo: "/repo", Items: []Item{
		{Path: "/repo/.wt/a", Branch: "a", Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
	}}}}

	Execute(context.Background(), f, p, ExecOptions{})

	if len(f.Calls) != 1 {
		t.Fatalf("Calls = %v", f.Calls)
	}
	want := "git -C /repo worktree remove --force /repo/.wt/a"
	if f.Calls[0].String() != want {
		t.Errorf("呼び出し = %q, want %q", f.Calls[0].String(), want)
	}
	if p.Deleted != 1 || p.DeleteFailed != 0 {
		t.Errorf("Deleted/Failed = %d/%d", p.Deleted, p.DeleteFailed)
	}
}

func TestExecuteContinuesAfterFailure(t *testing.T) {
	// 個別の失敗で止まらない。失敗件数は別に持つ
	f := execx.NewFake()
	f.On("git", execx.Result{ExitCode: 1, Stderr: "boom"})
	f.On("git", execx.Result{})
	p := &Plan{Repos: []RepoPlan{{Repo: "/repo", Items: []Item{
		{Path: "/a", Decision: Decision{Verdict: DELETE}},
		{Path: "/b", Decision: Decision{Verdict: DELETE}},
	}}}}

	Execute(context.Background(), f, p, ExecOptions{})

	if p.Deleted != 1 || p.DeleteFailed != 1 {
		t.Errorf("Deleted/Failed = %d/%d, want 1/1", p.Deleted, p.DeleteFailed)
	}
}

func TestExecutePrunesReposWithPrunable(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{}) // prune
	p := &Plan{Repos: []RepoPlan{{Repo: "/repo", Items: []Item{
		{Path: "/gone", Decision: Decision{Verdict: PRUNE}},
	}}}}

	Execute(context.Background(), f, p, ExecOptions{})

	if len(f.Calls) != 1 {
		t.Fatalf("Calls = %v", f.Calls)
	}
	if want := "git -C /repo worktree prune -v"; f.Calls[0].String() != want {
		t.Errorf("呼び出し = %q, want %q", f.Calls[0].String(), want)
	}
}

func TestExecuteNeverTouchesSkipOrKeep(t *testing.T) {
	// **locked を消さないことの最終防壁。** Classify が SKIP にしたものが
	// 実行側へ漏れないことを、実行側でも検査する
	f := execx.NewFake()
	p := &Plan{Repos: []RepoPlan{{Repo: "/repo", Items: []Item{
		{Path: "/locked", Decision: Decision{Verdict: SKIP, SkipKind: SkipLocked}},
		{Path: "/keep", Decision: Decision{Verdict: KEEP}},
	}}}}

	Execute(context.Background(), f, p, ExecOptions{})

	if len(f.Calls) != 0 {
		t.Errorf("SKIP/KEEP しか無いのにコマンドを呼んだ: %v", f.Calls)
	}
	if p.Executed != true {
		t.Error("Executed を立てていない")
	}
}

func mustMkdir(t *testing.T, p string) {
	t.Helper()
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatal(err)
	}
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s || strings.HasSuffix(x, s) {
			return true
		}
	}
	return false
}
