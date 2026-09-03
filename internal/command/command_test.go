// CLIは引数と終了コードの契約を守り、破壊操作をdry-run既定にする。
// stale binaryの警告はrepositoryを読めない環境で通常実行を妨げない。
package command

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// dispatcher の契約:
//   - stdout / stderr / exit code をテストから差し替えられる
//   - 通常結果は stdout、警告とエラーは stderr（Shell 版の規約に合わせる）
//   - 未知のサブコマンドは使い方を出して非0

func run(t *testing.T, r execx.Runner, args ...string) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := Run(context.Background(), args, Env{Stdout: &out, Stderr: &errOut, Runner: r})
	return code, out.String(), errOut.String()
}

func TestVersionPrintsCommitToStdout(t *testing.T) {
	f := execx.NewFake()
	code, out, errOut := run(t, f, "version")
	if code != 0 {
		t.Errorf("exit = %d, want 0 (stderr=%q)", code, errOut)
	}
	if !strings.Contains(out, "dotctl") {
		t.Errorf("stdout に名前が出ていない: %q", out)
	}
}

func TestHelpGoesToStdoutAndSucceeds(t *testing.T) {
	f := execx.NewFake()
	code, out, _ := run(t, f, "help")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "version") {
		t.Errorf("help にサブコマンド一覧が無い: %q", out)
	}
}

func TestNoArgsShowsUsageOnStderrAndFails(t *testing.T) {
	f := execx.NewFake()
	code, out, errOut := run(t, f)
	if code == 0 {
		t.Error("引数なしは非0で返してほしい")
	}
	if !strings.Contains(errOut, "使い方") {
		t.Errorf("使い方が stderr に出ていない: %q", errOut)
	}
	if out != "" {
		t.Errorf("エラー時に stdout を汚さない: %q", out)
	}
}

func TestUnknownSubcommandNamesItOnStderr(t *testing.T) {
	f := execx.NewFake()
	code, _, errOut := run(t, f, "frobnicate")
	if code == 0 {
		t.Error("未知のサブコマンドは非0で返してほしい")
	}
	if !strings.Contains(errOut, "frobnicate") {
		t.Errorf("何が未知だったか出ていない: %q", errOut)
	}
}

// --- version skew ---
//
// git pull でGo sourceが変わった後に再ビルドしないと、cron と hook は古いバイナリを黙って実行し
// 続ける（daily-update.sh が古い installs/<tool>/ の gh を掴んだ事故と同型）。
// 実行は止めず、stderr へ1行だけ警告する。

func TestWarnsWhenBuildInputsChanged(t *testing.T) {
	repo := t.TempDir()
	file := filepath.Join(repo, "main.go")
	os.WriteFile(file, []byte("package main\n"), 0o600)
	builtHash := currentSourceHash(repo, []string{"main.go"})
	os.WriteFile(file, []byte("package changed\n"), 0o600)
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "main.go\x00"})
	code, _, errOut := runWithBuild(t, f, "oldhash", repo, builtHash, "version")
	if code != 0 {
		t.Errorf("skew では実行を止めない: exit = %d", code)
	}
	if !strings.Contains(errOut, "再ビルド") {
		t.Errorf("再ビルドを促す警告が無い: %q", errOut)
	}
	if !strings.Contains(errOut, "dotctl rebuild") {
		t.Errorf("場所に依存しない再ビルドcommandを案内していない: %q", errOut)
	}
}

func TestSilentWhenOnlyNonBuildInputsChanged(t *testing.T) {
	repo := t.TempDir()
	os.WriteFile(filepath.Join(repo, "main.go"), []byte("package main\n"), 0o600)
	builtHash := currentSourceHash(repo, []string{"main.go"})
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "main.go\x00"})
	_, _, errOut := runWithBuild(t, f, "oldhash", repo, builtHash, "version")
	if errOut != "" {
		t.Errorf("build入力が同じなら何も言わない: %q", errOut)
	}
	want := "git -C " + repo + " ls-files -coz --exclude-standard -- *.go go.mod go.sum"
	if got := f.Calls[0].String(); got != want {
		t.Errorf("build入力だけを比較していない: %q, want %q", got, want)
	}
}

func TestSilentWhenRepoIsUnavailable(t *testing.T) {
	// リポジトリを消した端末・バイナリだけ配った端末で毎回警告を出さない
	f := execx.NewFake()
	f.On("git", execx.Result{ExitCode: 128, Stderr: "not a git repository"})
	_, _, errOut := runWithBuild(t, f, "oldhash", "/gone", "oldsource", "version")
	if errOut != "" {
		t.Errorf("repo が読めないときは黙る: %q", errOut)
	}
}

func TestSilentWhenBuildInfoIsAbsent(t *testing.T) {
	// go run や -ldflags なしのビルドで警告を出さない
	f := execx.NewFake()
	_, _, errOut := runWithBuild(t, f, "", "", "", "version")
	if errOut != "" {
		t.Errorf("ビルド情報が無いときは黙る: %q", errOut)
	}
	if len(f.Calls) != 0 {
		t.Errorf("ビルド情報が無ければ git を呼ばない: %v", f.Calls)
	}
}

func runWithBuild(t *testing.T, r execx.Runner, commit, repo, sourceHash string, args ...string) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errOut, Runner: r, Commit: commit, Repo: repo, SourceHash: sourceHash}
	code := Run(context.Background(), args, env)
	return code, out.String(), errOut.String()
}

// --- worktree cleanup の配線 ---

func TestWorktreeCleanupIsDryRunByDefault(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n"})

	code, out, _ := runEnv(t, Env{Runner: f, WorktreeRoots: "/repo", WorktreeRepos: []string{"/repo"}},
		"worktree", "cleanup")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "DRY-RUN") {
		t.Errorf("既定は dry-run: %q", out)
	}
	// **既定で削除コマンドを呼ばない**（安全側の既定が配線で崩れないこと）
	for _, c := range f.Calls {
		if strings.Contains(c.String(), "worktree remove") {
			t.Errorf("dry-run で remove を呼んでいる: %v", c)
		}
	}
}

func TestWorktreeCleanupExecuteRemoves(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n" +
		"worktree /repo/.wt/done\nbranch refs/heads/done\n\n"})
	f.On("git", execx.Result{Stdout: ""}) // tracked
	f.On("git", execx.Result{Stdout: ""}) // untracked
	f.On("gh", execx.Result{Stdout: "MERGED #1\n"})
	f.On("git", execx.Result{}) // remove

	code, out, _ := runEnv(t, Env{Runner: f, WorktreeRoots: "/repo", WorktreeRepos: []string{"/repo"}},
		"worktree", "cleanup", "--execute")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "EXECUTE") {
		t.Errorf("--execute のモード表示が無い: %q", out)
	}
	found := false
	for _, c := range f.Calls {
		if strings.Contains(c.String(), "worktree remove --force /repo/.wt/done") {
			found = true
		}
	}
	if !found {
		t.Errorf("remove を呼んでいない: %v", f.Calls)
	}
}

func TestWorktreeCleanupRejectsUnknownFlag(t *testing.T) {
	f := execx.NewFake()
	code, _, errOut := runEnv(t, Env{Runner: f}, "worktree", "cleanup", "--frobnicate")
	if code == 0 {
		t.Error("知らないオプションは非0で返してほしい")
	}
	if !strings.Contains(errOut, "--frobnicate") {
		t.Errorf("何が不正だったか出ていない: %q", errOut)
	}
}

func TestWorktreeCleanupHelpExits0(t *testing.T) {
	f := execx.NewFake()
	code, out, _ := runEnv(t, Env{Runner: f}, "worktree", "cleanup", "--help")
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	for _, want := range []string{"--execute", "--force", "--size"} {
		if !strings.Contains(out, want) {
			t.Errorf("使い方に %q が無い: %q", want, out)
		}
	}
}

func TestWorktreeWithoutSubcommandFails(t *testing.T) {
	f := execx.NewFake()
	code, _, errOut := runEnv(t, Env{Runner: f}, "worktree")
	if code == 0 {
		t.Error("サブコマンド無しは非0で返してほしい")
	}
	if !strings.Contains(errOut, "cleanup") {
		t.Errorf("使えるサブコマンドを出していない: %q", errOut)
	}
}

func runEnv(t *testing.T, env Env, args ...string) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	env.Stdout = &out
	env.Stderr = &errOut
	code := Run(context.Background(), args, env)
	return code, out.String(), errOut.String()
}

// --- private-bundle の引数解釈 ---

// **引数の足りない呼び出しで panic しないこと。** `args[2:]` を素朴に書いて
// slice bounds out of range で落ちた（パリティテストが捕まえた）。
func TestPrivateBundleDoesNotPanicOnMissingArgs(t *testing.T) {
	cases := [][]string{
		{"private-bundle"},
		{"private-bundle", "import"},
		{"private-bundle", "export", "--out"},
		{"private-bundle", "adopt"},
		{"private-bundle", "status"},
		{"private-bundle", "frobnicate"},
	}
	for _, args := range cases {
		t.Run(strings.Join(args, " "), func(t *testing.T) {
			f := execx.NewFake()
			// **panic すればここで落ちる。** 終了コードそのものは
			// 個別のテスト（TestPrivateBundleImportWithoutZipExitsOne など）が見る
			runEnv(t, Env{Runner: f}, args...)
		})
	}
}

func TestPrivateBundleImportWithoutZipExitsOne(t *testing.T) {
	// Shell 版と同じ終了コード（usage の 2 ではなく 1）
	f := execx.NewFake()
	code, _, errOut := runEnv(t, Env{Runner: f}, "private-bundle", "import")
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut, "zip がありません") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestPrivateBundleRejectsUnknownOption(t *testing.T) {
	f := execx.NewFake()
	for _, args := range [][]string{
		{"private-bundle", "adopt", "--bogus"},
		{"private-bundle", "export", "--bogus"},
	} {
		code, _, errOut := runEnv(t, Env{Runner: f}, args...)
		if code != 2 {
			t.Errorf("%v: exit = %d, want 2", args, code)
		}
		if !strings.Contains(errOut, "不明な引数") {
			t.Errorf("%v: stderr = %q", args, errOut)
		}
	}
}

// dry-run が案内する削除コマンドに、実行時のフラグを引き継ぐ。
func TestWorktreeCleanupDryRunSuggestsCommandWithFlags(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "/repo/.git\n"})
	f.On("git", execx.Result{Stdout: "worktree /repo\nbranch refs/heads/main\n\n"})

	_, out, _ := runEnv(t, Env{Runner: f, WorktreeRoots: "/repo", WorktreeRepos: []string{"/repo"}},
		"worktree", "cleanup", "--force")
	if !strings.Contains(out, "dotctl worktree cleanup --force --execute") {
		t.Errorf("案内コマンドに --force が残っていない: %q", out)
	}
}
