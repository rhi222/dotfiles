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
	"strconv"
	"strings"
	"time"

	"github.com/rhi222/dotfiles/internal/agentusage"
	"github.com/rhi222/dotfiles/internal/buildinfo"
	"github.com/rhi222/dotfiles/internal/command"
	"github.com/rhi222/dotfiles/internal/docker"
	"github.com/rhi222/dotfiles/internal/doctor"
	"github.com/rhi222/dotfiles/internal/execx"
	"github.com/rhi222/dotfiles/internal/privatebundle"
	"github.com/rhi222/dotfiles/internal/settings"
	"github.com/rhi222/dotfiles/internal/skill"
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

// vendorConfig は vendored skill の取込設定を解く。
// 環境変数は Shell 版と同じ名前にしてある（手元検証の手順を変えないため）。
func vendorConfig() skill.VendorConfig {
	home, _ := os.UserHomeDir()
	return skill.VendorConfig{
		VendorDir:  envOr("SKILL_VENDOR_DIR", repoPath(".config/claude/skills-vendor")),
		CacheDir:   envOr("SKILL_VENDOR_CACHE", filepath.Join(home, ".cache", "claude-skills-vendor")),
		SelfSkills: envOr("SKILL_VENDOR_SELF_SKILLS", repoPath(".config/claude/skills")),
		// symlink が張られる先。**3つ全部を見る**（agent ごとに探索先が違う）
		LiveDirs: []string{
			filepath.Join(home, ".claude", "skills"),
			filepath.Join(home, ".codex", "skills"),
			filepath.Join(home, ".agents", "skills"),
		},
		Today:   envOr("SKILL_VENDOR_DATE", today()),
		AutoYes: os.Getenv("SKILL_VENDOR_YES") == "1",
	}
}

func today() string { return time.Now().Format("2006-01-02") }

// residueConfig は残骸チェックの参照先を解く。
func residueConfig() doctor.ResidueConfig {
	home := homeDir()
	return doctor.ResidueConfig{
		Home:            home,
		Repo:            envOr("ENV_RESIDUE_REPO", resolveRepo()),
		FisherFilesFile: os.Getenv("ENV_RESIDUE_FISHER_FILES"),
		// **3つ全部を見る**（agent ごとに skill の探索先が違う）
		LiveSkillDirs: []string{
			filepath.Join(home, ".claude", "skills"),
			filepath.Join(home, ".codex", "skills"),
			filepath.Join(home, ".agents", "skills"),
		},
	}
}

// dockerConfig は docker 掃除の設定を解く。
//
// **閾値と除外リストは fish 側（99-local.fish）で設定される。** fish の変数は
// Go から読めないので、wrapper が環境変数へ移して渡す。
func dockerConfig() docker.Config {
	cfg := docker.DefaultConfig(homeDir())
	if v := os.Getenv("XDG_STATE_HOME"); v != "" {
		cfg.CacheFile = filepath.Join(v, "docker-clean", "stats.json")
	}
	if v := os.Getenv("DOCKER_CLEAN_CACHE_FILE"); v != "" {
		cfg.CacheFile = v
	}
	cfg.SizeThresholdGB = envFloat("DOCKER_CLEAN_SIZE_THRESHOLD_GB", cfg.SizeThresholdGB)
	cfg.UptimeThresholdH = envFloat("DOCKER_CLEAN_UPTIME_THRESHOLD_H", cfg.UptimeThresholdH)
	cfg.CacheTTLH = envFloat("DOCKER_CLEAN_CACHE_TTL_H", cfg.CacheTTLH)
	// **改行区切りで受ける。** グロブに空白が入ることは無いが、区切りを
	// 空白にすると将来の値で壊れる
	if v := os.Getenv("DOCKER_CLEAN_IGNORE_PATTERNS"); v != "" {
		var pats []string
		for _, p := range strings.Split(v, "\n") {
			if p = strings.TrimSpace(p); p != "" {
				pats = append(pats, p)
			}
		}
		if len(pats) > 0 {
			cfg.IgnorePatterns = pats
		}
	}
	return cfg
}

// agentUsageConfig は agent-usage の参照先を解く。
// 環境変数はテストと手元検証のための差し替え口。
func agentUsageConfig() agentusage.Config {
	home := homeDir()
	cacheDir := filepath.Join(home, ".cache")
	if v := os.Getenv("XDG_CACHE_HOME"); v != "" {
		cacheDir = v
	}
	return agentusage.Config{
		CacheFile:        envOr("AGENT_USAGE_CACHE", filepath.Join(cacheDir, "agent-usage", "usage.json")),
		CredentialsFile:  envOr("AGENT_USAGE_CLAUDE_CREDENTIALS", filepath.Join(home, ".claude", ".credentials.json")),
		CodexBin:         envOr("AGENT_USAGE_CODEX_BIN", "codex"),
		Endpoint:         envOr("AGENT_USAGE_ENDPOINT", "https://api.anthropic.com/api/oauth/usage"),
		TTL:              5 * time.Minute,
		StaleAfter:       15 * time.Minute,
		HTTPTimeout:      10 * time.Second,
	}
}

func fisherPaths() (string, string) {
	home := homeDir()
	cacheDir := envOr("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	return envOr("FISHER_PLUGIN_FILE", filepath.Join(home, ".config", "fish", "fish_plugins")),
		envOr("FISHER_CACHE_FILE", filepath.Join(cacheDir, "dotfiles", "fisher-update.refs"))
}

func envFloat(key string, def float64) float64 {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
	if err != nil {
		return def
	}
	return f
}

func homeDir() string {
	h, _ := os.UserHomeDir()
	return h
}

// privateConfig は集約先と起点を解く。
func privateConfig() privatebundle.Config {
	home, _ := os.UserHomeDir()
	return privatebundle.Config{
		PrivateDir: envOr("DOTFILES_PRIVATE_DIR",
			filepath.Join(home, ".local", "share", "dotfiles-private")),
		Home:    home,
		RepoDir: envOr("DOTFILES_DIR", resolveRepo()),
		// テスト専用。zip -e の代わりに -P を使う（-P は平文が ps に乗る）
		ZipPassword: os.Getenv("PRIVATE_BUNDLE_ZIP_PASSWORD"),
		Today:       today(),
	}
}

// repoPath はリポジトリ基準のパスを返す。
//
// **バイナリの場所からは解けない**（dotctl は ~/.local/bin にあり、そこに
// scripts/ は無い）。ビルド時に埋め込んだ Repo を第一に使う。
func repoPath(rel string) string {
	root := resolveRepo()
	if root == "" {
		return ""
	}
	return filepath.Join(root, rel)
}

var repoOnce struct {
	done bool
	root string
}

// resolveRepo はリポジトリのルートを解く。
//
// ビルド時に埋め込んだ値を優先し、無ければカレントディレクトリの git ルートへ
// 落とす。**この fallback が無いと ldflags 無しのビルド（go run、手元での
// go build、テスト）でリポジトリ相対のパスが全部空になり、allowlist が
// fail-closed で全部拒否になる。**
func resolveRepo() string {
	if repoOnce.done {
		return repoOnce.root
	}
	repoOnce.done = true

	if buildinfo.Repo != "" {
		repoOnce.root = buildinfo.Repo
		return repoOnce.root
	}
	res, err := execx.New().Run(context.Background(), execx.Cmd{
		Name: "git", Args: []string{"rev-parse", "--show-toplevel"},
	})
	if err == nil && res.OK() {
		repoOnce.root = strings.TrimSpace(res.Stdout)
	}
	return repoOnce.root
}

func cwd() string {
	d, err := os.Getwd()
	if err != nil {
		return ""
	}
	return d
}

func main() {
	selfExe, _ := os.Executable()
	fisherPluginFile, fisherCacheFile := fisherPaths()
	os.Exit(command.Run(context.Background(), os.Args[1:], command.Env{
		Stdout:     os.Stdout,
		Stderr:     os.Stderr,
		Runner:     execx.New(),
		Commit:     buildinfo.Commit,
		Repo:       envOr("DOTCTL_REPO", buildinfo.Repo),
		SourceHash: buildinfo.SourceHash,

		WorktreeRoots:      envOr("WORKTREE_CLEANUP_ROOTS", defaultWorktreeRoots),
		WorktreePRStateCmd: os.Getenv("WORKTREE_CLEANUP_PR_STATE_CMD"),
		WorktreeInitDir:    envOr("WORKTREE_INIT_D", defaultWorktreeInitDir()),
		Cwd:                cwd(),

		ClaudeSettings:  claudeSettings(),
		WindowsSettings: windowsSettings(),

		Vendor:            vendorConfig(),
		Private:           privateConfig(),
		HomeDir:           homeDir(),
		Residue:           residueConfig(),
		Docker:            dockerConfig(),
		TrustedOwnersFile: envOr("TRUSTED_SKILL_OWNERS_FILE", repoPath("scripts/trusted-skill-owners.txt")),

		AgentUsage:        agentUsageConfig(),
		AgentUsageSelfExe: selfExe,
		FisherPluginFile:  fisherPluginFile,
		FisherCacheFile:   fisherCacheFile,
		YaziPackageFile:   envOr("YAZI_PACKAGE_FILE", filepath.Join(homeDir(), ".config", "yazi", "package.toml")),
		YaziBin:           envOr("YAZI_BIN", "ya"),

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
