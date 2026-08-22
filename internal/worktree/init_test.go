// worktree initは対象とinstall commandを正規化し、dry-runではfileもhookも変更しない。
// custom hookの欠落や失敗で標準初期化まで失敗させない。
package worktree

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// origin URL の正規化。scp 形式・https・ssh のどれでも同じキーに解決する。
// **これがリポジトリ固有フックの探索キー**なので、形式によって食い違うと
// 「同じリポジトリなのに端末によってフックが走らない」が起きる。
func TestNormalizeRepoKey(t *testing.T) {
	tests := []struct{ in, want string }{
		{"git@github.com:owner/repo.git", "github.com/owner/repo"},
		{"git@github.com:owner/repo", "github.com/owner/repo"},
		{"https://github.com/owner/repo.git", "github.com/owner/repo"},
		{"https://github.com/owner/repo", "github.com/owner/repo"},
		{"http://github.com/owner/repo.git", "github.com/owner/repo"},
		{"ssh://git@github.com/owner/repo.git", "github.com/owner/repo"},
		{"git://github.com/owner/repo.git", "github.com/owner/repo"},
		// 自前ホスト（社内 GitLab のような形）
		{"git@git.example.com:group/sub/repo.git", "git.example.com/group/sub/repo"},
		{"https://user@git.example.com/group/repo.git", "git.example.com/group/repo"},
	}
	for _, tt := range tests {
		if got := normalizeRepoKey(tt.in); got != tt.want {
			t.Errorf("normalizeRepoKey(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

// lock ファイルから依存インストールのコマンドを決める。**優先順に意味がある**
// （pnpm と npm の lock が両方ある移行中のリポジトリで pnpm を選ぶ）。
func TestInstallCommand(t *testing.T) {
	tests := []struct {
		name  string
		files []string
		want  string
	}{
		{"pnpm", []string{"pnpm-lock.yaml"}, "pnpm install"},
		{"npm", []string{"package-lock.json"}, "npm ci"},
		{"yarn", []string{"yarn.lock"}, "yarn install"},
		{"pnpm が npm より優先", []string{"pnpm-lock.yaml", "package-lock.json"}, "pnpm install"},
		{"npm が yarn より優先", []string{"package-lock.json", "yarn.lock"}, "npm ci"},
		{"lock なし", nil, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			for _, f := range tt.files {
				if err := os.WriteFile(filepath.Join(dir, f), []byte("x"), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			if got := installCommand(dir); got != tt.want {
				t.Errorf("= %q, want %q", got, tt.want)
			}
		})
	}
}

// .env* の収集。**node_modules / .wt / .git は掘らない**（掘ると依存の中の
// .env を拾い、数千件を check-ignore に掛けることになる）。
func TestCollectEnvFiles(t *testing.T) {
	root := t.TempDir()
	write := func(rel string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(".env")
	write(".env.local")
	write("api/.env")
	write("api/nested/deep/.env.production")
	write("node_modules/pkg/.env")
	write(".wt/other/.env")
	write(".git/hooks/.env")
	write("notenv.txt")
	write("api/.environment") // .env* に一致する

	got := collectEnvFiles(root)

	want := []string{
		".env",
		".env.local",
		"api/.env",
		"api/.environment",
		"api/nested/deep/.env.production",
	}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("collectEnvFiles:\n got  %v\n want %v", got, want)
	}
}

func TestCollectEnvFilesIsSorted(t *testing.T) {
	// **並びは辞書順に固定する。** Shell 版は find のファイルシステム順なので
	// 出力順が端末ごとに変わりうる。決定的なほうが差分を読める
	root := t.TempDir()
	for _, rel := range []string{"z/.env", "a/.env", "m/.env"} {
		p := filepath.Join(root, rel)
		_ = os.MkdirAll(filepath.Dir(p), 0o755)
		_ = os.WriteFile(p, []byte("x"), 0o644)
	}
	got := collectEnvFiles(root)
	want := []string{"a/.env", "m/.env", "z/.env"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("got %v, want %v", got, want)
	}
}

// --- Init の分岐 ---

func runInit(t *testing.T, r execx.Runner, cfg InitConfig) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := Init(context.Background(), r, cfg, InitIO{Stdout: &out, Stderr: &errOut})
	return code, out.String(), errOut.String()
}

func TestInitRejectsNonRepo(t *testing.T) {
	f := execx.NewFake().On("git", execx.Result{ExitCode: 128, Stderr: "not a git repository"})
	code, _, errOut := runInit(t, f, InitConfig{Target: "/nope"})
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut, "gitリポジトリ内ではありません") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestInitRejectsMainWorktree(t *testing.T) {
	// **メイン worktree では走らせない。** ここで .env をコピーしても意味が無く、
	// 依存インストールが本体を触ってしまう
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "true\n"})    // is-inside-work-tree
	f.On("git", execx.Result{Stdout: "/r/.git\n"}) // --git-dir
	f.On("git", execx.Result{Stdout: "/r/.git\n"}) // --git-common-dir（同じ = メイン）
	code, _, errOut := runInit(t, f, InitConfig{Target: "/r"})
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut, "メインworktreeです") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestInitRejectsWhenMainWorktreeMissing(t *testing.T) {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "true\n"})
	f.On("git", execx.Result{Stdout: "/r/.git/worktrees/w\n"})
	f.On("git", execx.Result{Stdout: "/definitely/gone/.git\n"})
	code, _, errOut := runInit(t, f, InitConfig{Target: "/w"})
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut, "メインworktreeを特定できません") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestInitCustomHookSkipsWhenNoOrigin(t *testing.T) {
	main, target := setupInitDirs(t)
	f := initFakeGit(main, target)
	f.On("git", execx.Result{ExitCode: 1}) // remote get-url origin が失敗
	code, out, _ := runInit(t, f, InitConfig{Target: target})
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "custom: skip（origin未設定）") {
		t.Errorf("stdout = %q", out)
	}
}

func TestInitCustomHookSkipsWhenNoScript(t *testing.T) {
	main, target := setupInitDirs(t)
	f := initFakeGit(main, target)
	f.On("git", execx.Result{Stdout: "git@github.com:o/r.git\n"})
	code, out, _ := runInit(t, f, InitConfig{Target: target, InitDir: t.TempDir()})
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "custom: skip（github.com/o/r 用スクリプトなし）") {
		t.Errorf("stdout = %q", out)
	}
}

func TestInitCustomHookFailureDoesNotFailOverall(t *testing.T) {
	// **固有スクリプトが失敗しても worktree 作成フローは継続する。**
	// 初期化の一部が失敗しただけで worktree が使えなくなるほうが困る
	main, target := setupInitDirs(t)
	initDir := t.TempDir()
	scriptPath := filepath.Join(initDir, "github.com", "o", "r.sh")
	_ = os.MkdirAll(filepath.Dir(scriptPath), 0o755)
	_ = os.WriteFile(scriptPath, []byte("#!/bin/bash\nexit 1\n"), 0o755)

	f := initFakeGit(main, target)
	f.On("git", execx.Result{Stdout: "git@github.com:o/r.git\n"})
	f.On("bash", execx.Result{ExitCode: 1, Stderr: "boom"})

	code, _, errOut := runInit(t, f, InitConfig{Target: target, InitDir: initDir})
	if code != 0 {
		t.Errorf("exit = %d, want 0（継続する）", code)
	}
	if !strings.Contains(errOut, "custom hook が失敗しました") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestInitDryRunShowsCustomHookWithoutRunningIt(t *testing.T) {
	main, target := setupInitDirs(t)
	initDir := t.TempDir()
	script := filepath.Join(initDir, "github.com", "o", "r.sh")
	sentinel := filepath.Join(t.TempDir(), "custom-hook-ran")
	_ = os.MkdirAll(filepath.Dir(script), 0o755)
	_ = os.WriteFile(script, []byte("#!/bin/bash\ntouch "+sentinel+"\n"), 0o755)

	f := initFakeGit(main, target)
	f.On("git", execx.Result{Stdout: "git@github.com:o/r.git\n"})

	code, out, _ := runInit(t, f, InitConfig{Target: target, DryRun: true, InitDir: initDir})
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "[dry-run] custom: "+script) {
		t.Errorf("実行予定を出していない: %q", out)
	}
	for _, c := range f.Calls {
		if c.Name == "bash" {
			t.Error("dry-run なのに固有スクリプトを実行している")
		}
	}
	if _, err := os.Stat(sentinel); !os.IsNotExist(err) {
		t.Errorf("dry-run でcustom hookの副作用が発生した: %v", err)
	}
}

func TestInitDryRunTouchesNothing(t *testing.T) {
	main, target := setupInitDirs(t)
	if err := os.WriteFile(filepath.Join(main, ".env"), []byte("SECRET=1"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "pnpm-lock.yaml"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	f := initFakeGit(main, target)
	f.On("git", execx.Result{}) // check-ignore（ignore されている）
	f.On("git", execx.Result{ExitCode: 1})

	code, out, _ := runInit(t, f, InitConfig{Target: target, DryRun: true, InitDir: t.TempDir()})
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out, "[dry-run] copy: .env") {
		t.Errorf("copy の予定を出していない: %q", out)
	}
	if !strings.Contains(out, "[dry-run] install: pnpm install") {
		t.Errorf("install の予定を出していない: %q", out)
	}
	if _, err := os.Stat(filepath.Join(target, ".env")); err == nil {
		t.Error("dry-run なのにファイルをコピーしている")
	}
	// dry-run では install も走らせない
	for _, c := range f.Calls {
		if c.Name == "pnpm" {
			t.Error("dry-run なのに pnpm を呼んでいる")
		}
	}
}

func setupInitDirs(t *testing.T) (main, target string) {
	t.Helper()
	base := t.TempDir()
	main = filepath.Join(base, "main")
	target = filepath.Join(base, "wt")
	if err := os.MkdirAll(filepath.Join(main, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatal(err)
	}
	return main, target
}

// initFakeGit は Init の前段3回の git 呼び出し（work-tree 判定 / git-dir /
// git-common-dir）に応答する Fake を返す。
func initFakeGit(main, target string) *execx.Fake {
	f := execx.NewFake()
	f.On("git", execx.Result{Stdout: "true\n"})
	f.On("git", execx.Result{Stdout: filepath.Join(main, ".git", "worktrees", "w") + "\n"})
	f.On("git", execx.Result{Stdout: filepath.Join(main, ".git") + "\n"})
	return f
}
