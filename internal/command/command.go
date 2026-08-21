// Package command は dotctl のサブコマンドを組み立てる。
package command

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/rhi222/dotfiles/internal/docker"
	"github.com/rhi222/dotfiles/internal/doctor"
	"github.com/rhi222/dotfiles/internal/execx"
	"github.com/rhi222/dotfiles/internal/private"
	"github.com/rhi222/dotfiles/internal/settings"
	"github.com/rhi222/dotfiles/internal/skill"
)

// Env は dotctl が外界と触る面。**テストから全部差し替えられるようにする**
// のが目的で、実装側は os.Stdout や exec を直接触らない。
type Env struct {
	Stdout io.Writer
	Stderr io.Writer
	Runner execx.Runner

	// Commit / Repo はビルド時に埋め込まれた値（buildinfo）。
	// どちらかが空なら version skew の検知を行わない。
	Commit string
	Repo   string

	// WorktreeRoots は worktree の走査ルート（スペース区切り）。
	WorktreeRoots string
	// WorktreeRepos を渡すと走査を省いてこのリポジトリだけを見る（テスト用）。
	WorktreeRepos []string
	// WorktreePRStateCmd は PR 状態取得の差し替え口。
	WorktreePRStateCmd string
	// WorktreeInitDir はリポジトリ固有の初期化スクリプトの置き場。
	WorktreeInitDir string
	// Cwd はカレントディレクトリ（worktree init の既定の対象）。
	Cwd string

	// ClaudeSettings / WindowsSettings は設定同期の対象パス。
	ClaudeSettings  settings.ClaudeConfig
	WindowsSettings settings.WindowsConfig

	// Vendor は vendored skill の取込設定。
	Vendor skill.VendorConfig
	// TrustedOwnersFile は gh skill を自動更新してよい owner の allowlist。
	TrustedOwnersFile string

	// Private はローカル設定の集約（private bundle）の設定。
	Private private.Config
	// HomeDir は $HOME。
	HomeDir string
	// Residue は環境の残骸チェックの設定。
	Residue doctor.ResidueConfig
	// Docker は docker 掃除の設定。
	Docker docker.Config
	// ConfirmFunc は承認を取る（nil なら /dev/tty から読む）。テストで差し替える。
	ConfirmFunc func(prompt string) bool
	// Color は stdout が TTY のとき真。表示の着色に使う。
	Color bool
}

const usage = `使い方: dotctl <subcommand> [args...]

サブコマンド:
  worktree cleanup   消し忘れた git worktree を洗い出して掃除する
  worktree init      worktree 作成後の初期化
  settings sync      設定ファイルのコピー同期（claude / windows）
  skill audit        skill の内容を機械的に検査する
  skill vendor       vendored skill の取込と点検
  private-bundle     ローカル設定の集約と運搬
  wsl cleanup        WSL2 のキャッシュ掃除
  doctor residue     環境の残骸を洗い出す
  doctor migration   移行前チェック
  docker clean       docker の不要リソースを掃除する
  version            バイナリのビルド情報を出す
  help               この使い方を出す
`

// Run はサブコマンドを1つ実行して終了コードを返す。
//
// 規約は Shell 版に合わせる。通常結果は stdout、警告とエラーは stderr。
func Run(ctx context.Context, args []string, env Env) int {
	// **skew の警告はサブコマンドより先に出す。** 出力を読む人が
	// 「古い結果を見ている」ことに気付いてから中身を読めるようにする。
	warnIfStale(ctx, env)

	if len(args) == 0 {
		fmt.Fprint(env.Stderr, usage)
		return 2
	}

	switch args[0] {
	case "version":
		fmt.Fprintf(env.Stdout, "dotctl %s\n", versionString(env))
		return 0
	case "worktree":
		return runWorktree(ctx, args[1:], env)
	case "settings":
		return runSettings(ctx, args[1:], env)
	case "skill":
		return runSkill(ctx, args[1:], env)
	case "private-bundle":
		return runPrivateBundle(ctx, args[1:], env)
	case "wsl":
		return runWSL(ctx, args[1:], env)
	case "doctor":
		return runDoctor(ctx, args[1:], env)
	case "docker":
		return runDocker(ctx, args[1:], env)
	case "help", "-h", "--help":
		fmt.Fprint(env.Stdout, usage)
		return 0
	default:
		fmt.Fprintf(env.Stderr, "dotctl: 知らないサブコマンド: %s\n\n%s", args[0], usage)
		return 2
	}
}

func versionString(env Env) string {
	if env.Commit == "" {
		return "(ビルド情報なし)"
	}
	return env.Commit
}

// warnIfStale はバイナリのコミットと repo HEAD がずれていたら警告する。
//
// **実行は止めない。** cron を skew で落とすほうが害が大きいので、
// stderr へ1行出すだけにする。ビルド情報が無いとき（go run）と
// repo が読めないとき（リポジトリを消した端末、バイナリだけ配った端末）は
// 何も言わない。毎回警告が出る状態を作ると無視されるようになる。
func warnIfStale(ctx context.Context, env Env) {
	if env.Commit == "" || env.Repo == "" || env.Runner == nil {
		return
	}
	res, err := env.Runner.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"-C", env.Repo, "rev-parse", "HEAD"},
	})
	if err != nil || !res.OK() {
		return
	}
	head := strings.TrimSpace(res.Stdout)
	if head == "" || head == env.Commit {
		return
	}
	fmt.Fprintf(env.Stderr,
		"dotctl: バイナリが古い（%s、repo は %s）。再ビルド: bash scripts/setup-dotctl.sh\n",
		short(env.Commit), short(head))
}

func short(s string) string {
	if len(s) > 12 {
		return s[:12]
	}
	return s
}
