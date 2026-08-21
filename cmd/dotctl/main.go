// Command dotctl は dotfiles の運用コマンドをまとめた CLI。
//
// **入口は薄く保つ。** 分岐とロジックは internal/command 側にあり、
// ここは os の面（引数・標準出力・終了コード・環境変数・TTY 判定）を
// 渡すだけにする。そうすることで dispatcher 全体をテストから駆動できる。
package main

import (
	"context"
	"os"
	"path/filepath"

	"github.com/rhi222/dotfiles/internal/buildinfo"
	"github.com/rhi222/dotfiles/internal/command"
	"github.com/rhi222/dotfiles/internal/execx"
	"github.com/rhi222/dotfiles/internal/settings"
)

// defaultWorktreeRoots は worktree の走査ルート（Shell 版と同じ既定）。
const defaultWorktreeRoots = "/data/git-repos"

// defaultWorktreeInitDir はリポジトリ固有の初期化スクリプトの置き場。
//
// **バイナリの場所ではなくビルド元のリポジトリから解く。** dotctl は
// ~/.local/bin に置くので、バイナリ基準にすると ~/.local/scripts を見てしまう。
func defaultWorktreeInitDir() string {
	if buildinfo.Repo == "" {
		return ""
	}
	return filepath.Join(buildinfo.Repo, "scripts", "worktree-init.d")
}

// claudeSettings は ~/.claude/settings.json 同期のパスを解く。
// 環境変数はテストと手元検証のための差し替え口（Shell 版と同じ名前）。
func claudeSettings() settings.ClaudeConfig {
	home, _ := os.UserHomeDir()
	return settings.ClaudeConfig{
		Live: envOr("CLAUDE_SETTINGS_LIVE", filepath.Join(home, ".claude", "settings.json")),
		Repo: envOr("CLAUDE_SETTINGS_REPO", repoPath(".config/claude/settings.json")),
		SecretDict: envOr("SECRET_PATTERNS",
			filepath.Join(home, ".config", "dotfiles", "secret-patterns.txt")),
	}
}

// windowsSettings は Windows 側設定のパスを解く。
//
// **実ファイルのパス解決は環境変数が最優先。** テストが /mnt/c を触らずに
// 済むようにするため（Shell 版と同じ）。
func windowsSettings() settings.WindowsConfig {
	cfg := settings.WindowsConfig{
		WSLConfigLive: os.Getenv("WSLCONFIG_LIVE"),
		WSLConfigRepo: envOr("WSLCONFIG_REPO", repoPath(".config/wsl/.wslconfig")),
		TerminalLive:  os.Getenv("WT_SETTINGS_LIVE"),
		TerminalRepo:  envOr("WT_SETTINGS_REPO", repoPath(".config/windows-terminal/settings.json")),
	}
	// 環境変数が無いときだけ Windows 側を探す（cmd.exe の起動は遅いので）
	if cfg.WSLConfigLive == "" || cfg.TerminalLive == "" {
		user := settings.WinUser(context.Background(), execx.New())
		if user != "" {
			if cfg.WSLConfigLive == "" {
				cfg.WSLConfigLive = filepath.Join("/mnt/c/Users", user, ".wslconfig")
			}
			if cfg.TerminalLive == "" {
				cfg.TerminalLive = settings.FindTerminalSettings(user)
			}
		}
	}
	return cfg
}

// repoPath はビルド元リポジトリ基準のパスを返す。
// **バイナリの場所ではなくビルド元から解く**（dotctl は ~/.local/bin にある）。
func repoPath(rel string) string {
	if buildinfo.Repo == "" {
		return ""
	}
	return filepath.Join(buildinfo.Repo, rel)
}

func cwd() string {
	d, err := os.Getwd()
	if err != nil {
		return ""
	}
	return d
}

func main() {
	os.Exit(command.Run(context.Background(), os.Args[1:], command.Env{
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Runner: execx.New(),
		Commit: buildinfo.Commit,
		Repo:   buildinfo.Repo,

		WorktreeRoots:      envOr("WORKTREE_CLEANUP_ROOTS", defaultWorktreeRoots),
		WorktreePRStateCmd: os.Getenv("WORKTREE_CLEANUP_PR_STATE_CMD"),
		WorktreeInitDir:    envOr("WORKTREE_INIT_D", defaultWorktreeInitDir()),
		Cwd:                cwd(),

		ClaudeSettings:  claudeSettings(),
		WindowsSettings: windowsSettings(),

		Color: isTerminal(os.Stdout),
	}))
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// isTerminal は f が端末かどうか。**着色の判定はここだけで行う。**
// internal 側は Color フラグしか見ないので、テストで色を制御できる。
func isTerminal(f *os.File) bool {
	st, err := f.Stat()
	if err != nil {
		return false
	}
	return st.Mode()&os.ModeCharDevice != 0
}
