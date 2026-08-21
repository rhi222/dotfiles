// Package execx は外部コマンド実行の境界。
//
// **ここを1か所に集めるのが目的。** Shell 版は各所で直接コマンドを叩いていて、
// テストは PATH に stub を置く形になっていた。stub 方式には2つ問題がある。
// 実行されたコマンドの引数を検査できないこと、そして PATH という
// プロセス全体の状態を触るので並列実行で踏み合うこと。
package execx

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// Cmd は実行したい外部コマンド1つ。
type Cmd struct {
	Name  string
	Args  []string
	Dir   string // 空なら現在のディレクトリ
	Stdin string
}

// String は診断用の表示。Fake の呼び出し検査でも使う。
func (c Cmd) String() string {
	if len(c.Args) == 0 {
		return c.Name
	}
	return c.Name + " " + strings.Join(c.Args, " ")
}

// Result は実行結果。
type Result struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

// OK は正常終了したかどうか。
func (r Result) OK() bool { return r.ExitCode == 0 }

// Runner は外部コマンドを実行する。テストでは Fake を差し込む。
type Runner interface {
	Run(ctx context.Context, c Cmd) (Result, error)
}

type realRunner struct{}

// New は実際に外部プロセスを起動する Runner を返す。
func New() Runner { return realRunner{} }

// Run は外部コマンドを実行する。
//
// **非0終了はエラーにしない。** 「コマンドが失敗した」は多くの呼び出し元で
// 想定内の分岐（git がリポジトリでないと言う、gh が未認証だと言う）なので、
// Result.ExitCode で伝える。error を返すのは起動そのものができなかったとき
// （コマンドが無い、context がキャンセル済み）だけにして、呼び出し側が
// 「想定内の失敗」と「環境が壊れている」を区別できるようにする。
func (realRunner) Run(ctx context.Context, c Cmd) (Result, error) {
	cmd := exec.CommandContext(ctx, c.Name, c.Args...)
	cmd.Dir = c.Dir
	if c.Stdin != "" {
		cmd.Stdin = strings.NewReader(c.Stdin)
	}
	var out, errOut bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errOut

	err := cmd.Run()
	res := Result{Stdout: out.String(), Stderr: errOut.String()}

	var exitErr *exec.ExitError
	switch {
	case err == nil:
		return res, nil
	case errors.As(err, &exitErr):
		res.ExitCode = exitErr.ExitCode()
		return res, nil
	default:
		// 起動できなかった（コマンド不在・context キャンセル）
		return res, fmt.Errorf("%s: %w", c.Name, err)
	}
}

// ErrUnexpectedCommand は Fake に登録していないコマンドが呼ばれたときのエラー。
var ErrUnexpectedCommand = errors.New("execx: 登録していないコマンドが呼ばれた")

// Fake はテスト用の Runner。呼び出しを記録し、登録した結果を返す。
type Fake struct {
	// Calls は実行された Cmd を順に記録する。引数まで検査できる。
	Calls []Cmd

	byName map[string][]Result
	err    map[string]error
}

// NewFake は空の Fake を返す。
func NewFake() *Fake {
	return &Fake{byName: map[string][]Result{}, err: map[string]error{}}
}

// On はコマンド名に対して返す Result を登録する。複数回登録すると呼ばれた順に返す。
func (f *Fake) On(name string, r Result) *Fake {
	f.byName[name] = append(f.byName[name], r)
	return f
}

// OnError はコマンド名に対して起動エラーを登録する（コマンド不在の再現）。
func (f *Fake) OnError(name string, err error) *Fake {
	f.err[name] = err
	return f
}

// Run は登録内容に従って応答する。
//
// **登録していないコマンドは黙って成功させない。** 空の Result を返すと
// 「呼ばれていないのに通った」テストができてしまい、テストが嘘をつく。
func (f *Fake) Run(_ context.Context, c Cmd) (Result, error) {
	f.Calls = append(f.Calls, c)

	if err, ok := f.err[c.Name]; ok {
		return Result{}, err
	}
	rs, ok := f.byName[c.Name]
	if !ok || len(rs) == 0 {
		return Result{}, fmt.Errorf("%w: %s", ErrUnexpectedCommand, c)
	}
	r := rs[0]
	if len(rs) > 1 {
		f.byName[c.Name] = rs[1:]
	}
	return r, nil
}
