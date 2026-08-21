package execx

import (
	"context"
	"errors"
	"strings"
	"testing"
)

// 外部コマンド実行は「境界」として1か所に集める。Shell 版は各所で直接
// コマンドを叩いていて、テストが PATH に stub を置く形になっていた。
// stub 方式は実行されたコマンドの引数を検査できず、並列実行で踏み合う。

func TestRealRunnerCapturesStdoutAndExitCode(t *testing.T) {
	r := New()
	got, err := r.Run(context.Background(), Cmd{Name: "sh", Args: []string{"-c", "echo out; echo err >&2; exit 3"}})
	if err != nil {
		t.Fatalf("非0終了はエラーにしない（Result で伝える）: %v", err)
	}
	if strings.TrimSpace(got.Stdout) != "out" {
		t.Errorf("Stdout = %q, want %q", got.Stdout, "out")
	}
	if strings.TrimSpace(got.Stderr) != "err" {
		t.Errorf("Stderr = %q, want %q", got.Stderr, "err")
	}
	if got.ExitCode != 3 {
		t.Errorf("ExitCode = %d, want 3", got.ExitCode)
	}
}

func TestRealRunnerRunsInDir(t *testing.T) {
	dir := t.TempDir()
	r := New()
	got, err := r.Run(context.Background(), Cmd{Name: "pwd", Dir: dir})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	// macOS の /var -> /private/var のような symlink を避けるため後方一致で見る
	if !strings.HasSuffix(strings.TrimSpace(got.Stdout), strings.TrimPrefix(dir, "/private")) {
		t.Errorf("Dir が効いていない: Stdout = %q, want suffix %q", got.Stdout, dir)
	}
}

func TestRealRunnerReportsMissingCommand(t *testing.T) {
	r := New()
	_, err := r.Run(context.Background(), Cmd{Name: "definitely-not-a-real-command-xyz"})
	if err == nil {
		t.Fatal("コマンドが無い場合はエラーを返してほしい（非0終了とは区別する）")
	}
}

func TestRealRunnerHonorsContextCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	r := New()
	_, err := r.Run(ctx, Cmd{Name: "sleep", Args: []string{"5"}})
	if err == nil {
		t.Fatal("キャンセル済み context では即座にエラーを返してほしい")
	}
}

func TestFakeReturnsProgrammedResultAndRecordsCalls(t *testing.T) {
	f := NewFake()
	f.On("git", Result{Stdout: "abc123\n"})

	got, err := f.Run(context.Background(), Cmd{Name: "git", Args: []string{"rev-parse", "HEAD"}})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if got.Stdout != "abc123\n" {
		t.Errorf("Stdout = %q", got.Stdout)
	}
	if len(f.Calls) != 1 {
		t.Fatalf("Calls = %d, want 1", len(f.Calls))
	}
	// **引数を検査できることが stub 方式との差**
	if want := "git rev-parse HEAD"; f.Calls[0].String() != want {
		t.Errorf("Calls[0] = %q, want %q", f.Calls[0].String(), want)
	}
}

func TestFakeFailsLoudlyOnUnexpectedCommand(t *testing.T) {
	f := NewFake()
	_, err := f.Run(context.Background(), Cmd{Name: "curl"})
	if err == nil {
		t.Fatal("登録していないコマンドは黙って成功させない（テストが嘘をつく）")
	}
	if !errors.Is(err, ErrUnexpectedCommand) {
		t.Errorf("err = %v, want ErrUnexpectedCommand", err)
	}
}
