// Package command は dotctl のサブコマンドを組み立てる。
package command

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/rhi222/dotfiles/internal/agentusage"
	"github.com/rhi222/dotfiles/internal/docker"
	"github.com/rhi222/dotfiles/internal/doctor"
	"github.com/rhi222/dotfiles/internal/execx"
	"github.com/rhi222/dotfiles/internal/pluginvendor"
	"github.com/rhi222/dotfiles/internal/privatebundle"
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
	Commit     string
	Repo       string
	SourceHash string

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

	// ClaudeSettings / CodexSettings / WindowsSettings は設定同期の対象パス。
	ClaudeSettings  settings.ClaudeConfig
	CodexSettings   settings.CodexConfig
	WindowsSettings settings.WindowsConfig

	// Vendor は vendored skill の取込設定。
	Vendor skill.VendorConfig
	// PluginVendor は vendored agent plugin の更新設定。
	PluginVendor pluginvendor.Config
	// TrustedOwnersFile は gh skill を自動更新してよい owner の allowlist。
	TrustedOwnersFile string

	// Private はローカル設定の集約（private bundle）の設定。
	Private privatebundle.Config
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

	// AgentUsage は agent-usage の参照先。
	AgentUsage agentusage.Config
	// AgentUsageSelfExe は detached refresh 用の自分自身のパス（os.Executable）。
	AgentUsageSelfExe string
	// AgentUsageNoSpawn はテスト用に外部プロセス起動を止める。
	AgentUsageNoSpawn bool

	// FisherPluginFile / FisherCacheFile はfisher-updateの宣言と前回成功state。
	FisherPluginFile string
	FisherCacheFile  string
	// YaziPackageFile / YaziBin はyazi-updateの宣言と実行command。
	YaziPackageFile string
	YaziBin         string
}

const usage = `使い方: dotctl <subcommand> [args...]

サブコマンド:
  worktree cleanup   消し忘れた git worktree を洗い出して掃除する
  worktree init      worktree 作成後の初期化
  settings sync      設定ファイルの同期・比較（claude / codex / windows）
  skill audit        skill の内容を機械的に検査する
  skill vendor       vendored skill の取込と点検
  plugin vendor      vendored agent plugin の更新と点検
  private-bundle     ローカル設定の集約と運搬
  wsl cleanup        WSL2 のキャッシュ掃除
  doctor residue     環境の残骸を洗い出す
  doctor migration   移行前チェック
  docker clean       docker の不要リソースを掃除する
  agent-usage        AI agent のレート上限を表示する（herdr 連携）
  session nvim-plan  nvim のherdr復元計画をJSONで出す
  fisher-update      変更があるときだけfish pluginを更新する
  yazi-update        変更があるときだけyazi packageを更新する
  rebuild            ビルド元のrepositoryからdotctlを再ビルドする
  version            バイナリのビルド情報を出す
  help               この使い方を出す
`

// Run はサブコマンドを1つ実行して終了コードを返す。
//
// 規約は Shell 版に合わせる。通常結果は stdout、警告とエラーは stderr。
func Run(ctx context.Context, args []string, env Env) int {
	// **skew の警告はサブコマンドより先に出す。** 出力を読む人が
	// 「古い結果を見ている」ことに気付いてから中身を読めるようにする。
	// rebuild 自体は skew を解消する操作なので、同じ警告を重ねない。
	if len(args) == 0 || args[0] != "rebuild" {
		warnIfStale(ctx, env)
	}

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
	case "plugin":
		return runPlugin(ctx, args[1:], env)
	case "private-bundle":
		return runPrivateBundle(ctx, args[1:], env)
	case "wsl":
		return runWSL(ctx, args[1:], env)
	case "doctor":
		return runDoctor(ctx, args[1:], env)
	case "docker":
		return runDocker(ctx, args[1:], env)
	case "agent-usage":
		return runAgentUsage(ctx, args[1:], env)
	case "session":
		return runSession(args[1:], env)
	case "fisher-update":
		return runFisherUpdate(ctx, args[1:], env)
	case "yazi-update":
		return runYaziUpdate(ctx, args[1:], env)
	case "rebuild":
		return runRebuild(ctx, args[1:], env)
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
	if env.SourceHash != "" {
		return env.Commit + " " + env.SourceHash
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
		"dotctl: バイナリが古い（%s、repo は %s）。再ビルド: dotctl rebuild\n",
		short(env.Commit), short(head))
}

func short(s string) string {
	if len(s) > 12 {
		return s[:12]
	}
	return s
}
