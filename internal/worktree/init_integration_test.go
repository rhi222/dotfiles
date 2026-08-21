package worktree

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

// 実 git リポジトリと実ファイルを使う検査。
//
// **ここに残すのは「実際の git と filesystem でしか確かめられないもの」だけ。**
// 分岐は init_test.go の unit test が持つ。-short では飛ばすので、
// setup-dotctl.sh のビルド前ゲート（go test -short）は速いままになる。

func TestInitCopiesIgnoredEnvFilesForReal(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	main, target := setupRealWorktree(t)

	// gitignore 対象の .env 系（コピーされる）
	writeFile(t, filepath.Join(main, ".env"), "SECRET=main", 0o600)
	writeFile(t, filepath.Join(main, "api", ".env.local"), "APP=1", 0o644)
	// 追跡されている .env.example（check-ignore に該当しないのでコピーされない）
	writeFile(t, filepath.Join(main, ".env.example"), "EXAMPLE=1", 0o644)
	git(t, main, "add", "-f", ".env.example")
	git(t, main, "commit", "-qm", "add example")
	// 掘らないディレクトリの中（拾わない）
	writeFile(t, filepath.Join(main, "node_modules", "pkg", ".env"), "NOPE=1", 0o644)

	out := runRealInit(t, InitConfig{Target: target})

	if _, err := os.Stat(filepath.Join(target, ".env")); err != nil {
		t.Errorf(".env がコピーされていない: %v\n%s", err, out)
	}
	if _, err := os.Stat(filepath.Join(target, "api", ".env.local")); err != nil {
		t.Errorf("入れ子の .env.local がコピーされていない: %v\n%s", err, out)
	}
	// **追跡ファイルはコピーしない。** worktree には既にあるので上書きの危険しかない
	if strings.Contains(out, ".env.example") {
		t.Errorf("追跡ファイルをコピー対象にしている:\n%s", out)
	}
	if strings.Contains(out, "node_modules") {
		t.Errorf("node_modules を掘っている:\n%s", out)
	}

	// **権限を保つ。** .env は秘密を持つので落として配ってはいけない
	st, err := os.Stat(filepath.Join(target, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Mode().Perm(); got != 0o600 {
		t.Errorf("権限 = %o, want 600", got)
	}
}

func TestInitIsIdempotent(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	main, target := setupRealWorktree(t)
	writeFile(t, filepath.Join(main, ".env"), "SECRET=main", 0o600)
	// worktree 側に既にある（手で書いた）ファイルは上書きしない
	writeFile(t, filepath.Join(target, ".env"), "SECRET=wt-local", 0o600)

	out := runRealInit(t, InitConfig{Target: target})

	if !strings.Contains(out, "skip (既存): .env") {
		t.Errorf("既存を skip したと言っていない:\n%s", out)
	}
	got := readFile(t, filepath.Join(target, ".env"))
	if got != "SECRET=wt-local" {
		t.Errorf("既存ファイルを上書きした: %q", got)
	}
}

func TestInitRunsCustomHookForReal(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git と bash を使うので -short では飛ばす")
	}
	main, target := setupRealWorktree(t)
	git(t, main, "remote", "add", "origin", "git@github.com:example-org/example-repo.git")

	initDir := t.TempDir()
	script := filepath.Join(initDir, "github.com", "example-org", "example-repo.sh")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, script, "#!/bin/bash\necho \"CUSTOM_RAN target=$1\"\n", 0o755)

	out := runRealInit(t, InitConfig{Target: target, InitDir: initDir})

	if !strings.Contains(out, "CUSTOM_RAN") {
		t.Errorf("固有スクリプトが走っていない:\n%s", out)
	}
	// **第1引数に worktree パスが渡る**（固有スクリプトの契約）
	if !strings.Contains(out, "target="+target) {
		t.Errorf("worktree パスが渡っていない:\n%s", out)
	}
}

func TestInitRejectsMainWorktreeForReal(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	main, _ := setupRealWorktree(t)

	var out, errOut bytes.Buffer
	code := Init(context.Background(), execx.New(), InitConfig{Target: main},
		InitIO{Stdout: &out, Stderr: &errOut})

	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "メインworktreeです") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

// --- ヘルパー ---

func setupRealWorktree(t *testing.T) (main, target string) {
	t.Helper()
	base := t.TempDir()
	main = filepath.Join(base, "main")
	if err := os.MkdirAll(main, 0o755); err != nil {
		t.Fatal(err)
	}
	git(t, main, "init", "-q")
	git(t, main, "config", "user.email", "test@example.com")
	git(t, main, "config", "user.name", "test")
	writeFile(t, filepath.Join(main, ".gitignore"), ".env\n.env.*\n", 0o644)
	writeFile(t, filepath.Join(main, "README"), "x", 0o644)
	git(t, main, "add", "-A")
	git(t, main, "commit", "-qm", "init")

	target = filepath.Join(base, "wt")
	git(t, main, "worktree", "add", "-q", "-b", "feat", target)
	return main, target
}

func runRealInit(t *testing.T, cfg InitConfig) string {
	t.Helper()
	var out, errOut bytes.Buffer
	code := Init(context.Background(), execx.New(), cfg, InitIO{Stdout: &out, Stderr: &errOut})
	if code != 0 {
		t.Fatalf("exit = %d\nstdout:\n%s\nstderr:\n%s", code, out.String(), errOut.String())
	}
	return out.String() + errOut.String()
}

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, b)
	}
}

func writeFile(t *testing.T, path, body string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
