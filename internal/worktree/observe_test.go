package worktree

import (
	"context"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// git worktree list --porcelain の解析。
//
// **main worktree を除外することと、detached の空 branch を保つことが要点。**
// Shell 版は TSV に落としてから読み直していて、TAB が IFS の空白文字である
// ために detached の空フィールドが畳まれてフィールドがずれるバグを踏んでいた。
// Go では構造体のまま持つのでその失敗の余地が無い。

const porcelainSample = `worktree /repo
HEAD abc
branch refs/heads/main

worktree /repo/.wt/feat-a
HEAD def
branch refs/heads/feat-a

worktree /repo/.wt/detached-one
HEAD 111
detached

worktree /repo/.wt/locked-one
HEAD 222
branch refs/heads/locked-one
locked claude session

worktree /repo/.wt/gone
HEAD 333
branch refs/heads/gone
prunable gitdir file points to non-existent location

`

func TestParseWorktreesExcludesMainAndKeepsFields(t *testing.T) {
	got := parseWorktrees(porcelainSample, "/repo")

	if len(got) != 4 {
		t.Fatalf("件数 = %d, want 4 (main を除く): %+v", len(got), got)
	}

	want := []struct {
		path     string
		branch   string
		locked   bool
		lockDet  string
		prunable bool
		pruneDet string
	}{
		{path: "/repo/.wt/feat-a", branch: "feat-a"},
		{path: "/repo/.wt/detached-one", branch: ""},
		{path: "/repo/.wt/locked-one", branch: "locked-one", locked: true, lockDet: "claude session"},
		{path: "/repo/.wt/gone", branch: "gone", prunable: true, pruneDet: "gitdir file points to non-existent location"},
	}
	for i, w := range want {
		g := got[i]
		if g.Path != w.path || g.Branch != w.branch {
			t.Errorf("[%d] Path/Branch = %q/%q, want %q/%q", i, g.Path, g.Branch, w.path, w.branch)
		}
		if g.Locked != w.locked || g.LockDetail != w.lockDet {
			t.Errorf("[%d] Locked = %v/%q, want %v/%q", i, g.Locked, g.LockDetail, w.locked, w.lockDet)
		}
		if g.Prunable != w.prunable || g.PruneDetail != w.pruneDet {
			t.Errorf("[%d] Prunable = %v/%q, want %v/%q", i, g.Prunable, g.PruneDetail, w.prunable, w.pruneDet)
		}
	}
}

func TestParseWorktreesHandlesLockedWithoutDetail(t *testing.T) {
	in := "worktree /repo\nbranch refs/heads/main\n\nworktree /repo/.wt/x\nbranch refs/heads/x\nlocked\n\n"
	got := parseWorktrees(in, "/repo")
	if len(got) != 1 {
		t.Fatalf("件数 = %d, want 1", len(got))
	}
	if !got[0].Locked || got[0].LockDetail != "" {
		t.Errorf("Locked = %v, detail = %q; want true, \"\"", got[0].Locked, got[0].LockDetail)
	}
}

func TestParseWorktreesHandlesMissingTrailingBlankLine(t *testing.T) {
	// 最後のレコードの後ろに空行が無い入力（コマンド置換で末尾改行が落ちた形）
	in := "worktree /repo\nbranch refs/heads/main\n\nworktree /repo/.wt/x\nbranch refs/heads/x"
	got := parseWorktrees(in, "/repo")
	if len(got) != 1 {
		t.Fatalf("末尾の空行が無くても最後のレコードを確定してほしい: %+v", got)
	}
}

// --- PR 状態 ---

func TestPRStateParsing(t *testing.T) {
	tests := []struct {
		out  string
		want PRKind
		raw  string
	}{
		{"MERGED #10737\n", PRMerged, "MERGED #10737"},
		{"CLOSED #99\n", PRClosed, "CLOSED #99"},
		{"OPEN #11068\n", PROpen, "OPEN #11068"},
		{"NONE\n", PRNone, "NONE"},
	}
	for _, tt := range tests {
		t.Run(tt.out, func(t *testing.T) {
			f := execx.NewFake().On("gh", execx.Result{Stdout: tt.out})
			got := prState(context.Background(), f, "/repo", "b", "")
			if got.Kind != tt.want {
				t.Errorf("Kind = %v, want %v", got.Kind, tt.want)
			}
			if got.Raw != tt.raw {
				t.Errorf("Raw = %q, want %q", got.Raw, tt.raw)
			}
		})
	}
}

func TestPRStateUnavailableOnFailure(t *testing.T) {
	// gh が非0 / 未認証 / 空出力のいずれも「取得できなかった」に倒す。
	// **判定不能を DELETE 側に倒さないため、ここは KEEP の材料になる。**
	for name, res := range map[string]execx.Result{
		"非0で返る": {ExitCode: 1, Stderr: "gh: not authenticated"},
		"空を返す":  {Stdout: "\n"},
	} {
		t.Run(name, func(t *testing.T) {
			f := execx.NewFake().On("gh", res)
			if got := prState(context.Background(), f, "/repo", "b", ""); got.Kind != PRUnavailable {
				t.Errorf("Kind = %v, want PRUnavailable", got.Kind)
			}
		})
	}
}

func TestPRStateUsesOverrideCommand(t *testing.T) {
	// テストや手元検証用の差し替え口（Shell 版の WORKTREE_CLEANUP_PR_STATE_CMD）
	f := execx.NewFake().On("my-stub", execx.Result{Stdout: "MERGED #7\n"})
	got := prState(context.Background(), f, "/repo", "feat", "my-stub")
	if got.Kind != PRMerged {
		t.Fatalf("Kind = %v, want PRMerged", got.Kind)
	}
	if len(f.Calls) != 1 {
		t.Fatalf("Calls = %d", len(f.Calls))
	}
	if want := "my-stub /repo feat"; f.Calls[0].String() != want {
		t.Errorf("呼び出し = %q, want %q", f.Calls[0].String(), want)
	}
}

func TestPRStateDoesNotCallGhWhenOverridden(t *testing.T) {
	f := execx.NewFake().On("my-stub", execx.Result{Stdout: "NONE\n"})
	prState(context.Background(), f, "/repo", "feat", "my-stub")
	for _, c := range f.Calls {
		if c.Name == "gh" {
			t.Error("差し替え口が指定されているのに gh を呼んでいる")
		}
	}
}

// --- 未追跡件数 ---

func TestUntrackedCount(t *testing.T) {
	f := execx.NewFake().On("git", execx.Result{Stdout: "?? a\n?? b\n M c\n"})
	if got := untrackedCount(context.Background(), f, "/p"); got != 2 {
		t.Errorf("= %d, want 2（?? の行だけ数える）", got)
	}
}

func TestUntrackedCountIsZeroWhenUnreadable(t *testing.T) {
	// 測れないときは 0。**呼び出し側が数値として扱うので、ここで曖昧にしない**
	f := execx.NewFake().On("git", execx.Result{ExitCode: 128, Stderr: "not a git repository"})
	if got := untrackedCount(context.Background(), f, "/p"); got != 0 {
		t.Errorf("= %d, want 0", got)
	}
}

func TestHasTrackedChangesIgnoresUntracked(t *testing.T) {
	// --untracked-files=no を使うので、?? だけの出力は「変更なし」
	f := execx.NewFake().On("git", execx.Result{Stdout: ""})
	if hasTrackedChanges(context.Background(), f, "/p") {
		t.Error("空出力なら追跡変更なし")
	}
	f2 := execx.NewFake().On("git", execx.Result{Stdout: " M file\n"})
	if !hasTrackedChanges(context.Background(), f2, "/p") {
		t.Error("追跡変更ありを拾えていない")
	}
}
