// doctorは残骸と移行対象を検出しつつ、宣言を読めない場合は誤検知しない側へ倒す。
// 情報提供のresidueと異常を示すmigrationの終了コードを混同しない。
package doctor

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

func residueSetup(t *testing.T) ResidueConfig {
	t.Helper()
	base := t.TempDir()
	cfg := ResidueConfig{
		Home: filepath.Join(base, "home"),
		Repo: filepath.Join(base, "repo"),
		LiveSkillDirs: []string{
			filepath.Join(base, "home", ".claude", "skills"),
			filepath.Join(base, "home", ".agents", "skills"),
		},
	}
	if err := os.MkdirAll(cfg.Home, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(cfg.Repo, "scripts", "setup"), 0o755); err != nil {
		t.Fatal(err)
	}
	// 宣言が読めないと skill の判定を諦めるので、空でも置いておく
	if err := os.WriteFile(filepath.Join(cfg.Repo, "scripts", "setup", "claude-skills.txt"),
		[]byte("# 宣言\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return cfg
}

func check(t *testing.T, cfg ResidueConfig, f *execx.Fake) ([]Residue, []string) {
	t.Helper()
	if f == nil {
		f = execx.NewFake()
	}
	return CheckResidue(context.Background(), f, cfg)
}

func messages(found []Residue) string {
	var b strings.Builder
	for _, f := range found {
		b.WriteString(f.Message + "\n")
	}
	return b.String()
}

func TestResidueDetectsOldFzf(t *testing.T) {
	// **mise 管理と二重になり、PATH 順で古い版を掴む端末が出る。**
	cfg := residueSetup(t)
	if err := os.MkdirAll(filepath.Join(cfg.Home, ".fzf"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cfg.Home, ".fzf.bash"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	found, _ := check(t, cfg, nil)
	msg := messages(found)
	if !strings.Contains(msg, "~/.fzf/ が残っています") {
		t.Errorf("~/.fzf を検出しない: %q", msg)
	}
	if !strings.Contains(msg, "~/.fzf.bash が残っています") {
		t.Errorf("~/.fzf.bash を検出しない: %q", msg)
	}
	// 撤去手順を出す（消してよいか判断できるように）
	for _, f := range found {
		if f.Hint == "" {
			t.Errorf("撤去手順が無い: %+v", f)
		}
	}
}

func TestResidueIsQuietOnCleanEnvironment(t *testing.T) {
	cfg := residueSetup(t)
	found, notes := check(t, cfg, nil)
	if len(found) != 0 {
		t.Errorf("綺麗な環境で検出した: %+v", found)
	}
	if len(notes) != 0 {
		t.Errorf("注記が出た: %+v", notes)
	}
}

// **fisher の判定は名前の規約ではなく fisher 自身が持つ一覧で行う。**
// 「`_` 始まりはプラグイン」で切った初版は tide の fish_prompt / tide、
// fisher 本体、fzf.fish の fzf_configure_bindings を誤検知した（実環境で5件）。
func TestResidueUsesFisherManifestNotNamingConvention(t *testing.T) {
	cfg := residueSetup(t)
	liveDir := filepath.Join(cfg.Home, ".config", "fish", "functions")
	if err := os.MkdirAll(liveDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// fisher が入れた公開関数（普通の名前）
	for _, n := range []string{"fish_prompt.fish", "tide.fish", "fisher.fish", "fzf_configure_bindings.fish"} {
		if err := os.WriteFile(filepath.Join(liveDir, n), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// fisher の管理下に無い残骸
	if err := os.WriteFile(filepath.Join(liveDir, "fish_user_key_bindings.fish"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	manifest := filepath.Join(t.TempDir(), "fisher-files")
	body := ""
	for _, n := range []string{"fish_prompt.fish", "tide.fish", "fisher.fish", "fzf_configure_bindings.fish"} {
		body += filepath.Join(liveDir, n) + "\n"
	}
	if err := os.WriteFile(manifest, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg.FisherFilesFile = manifest

	found, _ := check(t, cfg, nil)
	msg := messages(found)
	for _, n := range []string{"fish_prompt", "tide.fish", "fisher.fish", "fzf_configure_bindings"} {
		if strings.Contains(msg, n) {
			t.Errorf("fisher の公開関数を誤検知した（%s）: %q", n, msg)
		}
	}
	if !strings.Contains(msg, "fish_user_key_bindings.fish") {
		t.Errorf("本当の残骸を検出しない: %q", msg)
	}
}

func TestResidueFallsBackToNamingWhenManifestUnavailable(t *testing.T) {
	// 一覧が引けない環境では `_` 始まりの除外に落とす。**報告漏れより
	// 誤検知のほうがましだが、そもそも fish が無ければ問題にならない。**
	cfg := residueSetup(t)
	liveDir := filepath.Join(cfg.Home, ".config", "fish", "functions")
	if err := os.MkdirAll(liveDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, n := range []string{"_private.fish", "stray.fish"} {
		if err := os.WriteFile(filepath.Join(liveDir, n), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// fish が無い Runner
	f := execx.NewFake().OnError("fish", os.ErrNotExist)

	found, _ := check(t, cfg, f)
	msg := messages(found)
	if strings.Contains(msg, "_private.fish") {
		t.Errorf("_ 始まりを報告した: %q", msg)
	}
	if !strings.Contains(msg, "stray.fish") {
		t.Errorf("残骸を検出しない: %q", msg)
	}
}

func TestResidueIgnoresFunctionsShadowedByRepo(t *testing.T) {
	// repo の my/functions が同名を持つものは影にできていて実害が無い
	cfg := residueSetup(t)
	liveDir := filepath.Join(cfg.Home, ".config", "fish", "functions")
	repoDir := filepath.Join(cfg.Repo, ".config", "fish", "my", "functions")
	for _, d := range []string{liveDir, repoDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, d := range []string{liveDir, repoDir} {
		if err := os.WriteFile(filepath.Join(d, "gf.fish"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	found, _ := check(t, cfg, execx.NewFake().OnError("fish", os.ErrNotExist))
	if strings.Contains(messages(found), "gf.fish") {
		t.Errorf("影にできている関数を報告した: %q", messages(found))
	}
}

func TestResidueDetectsUndeclaredSkill(t *testing.T) {
	cfg := residueSetup(t)
	live := cfg.LiveSkillDirs[0]
	if err := os.MkdirAll(filepath.Join(live, "mystery-skill"), 0o755); err != nil {
		t.Fatal(err)
	}

	found, _ := check(t, cfg, nil)
	msg := messages(found)
	if !strings.Contains(msg, "宣言に無い skill") || !strings.Contains(msg, "mystery-skill") {
		t.Errorf("宣言に無い skill を検出しない: %q", msg)
	}
}

func TestResidueDetectsVendoredAsRealDirectory(t *testing.T) {
	// **これが実際に6本起きていた。** vendored は symlink で入るのが正で、
	// 実ディレクトリなら古い gh 版が読まれ続ける
	cfg := residueSetup(t)
	if err := os.MkdirAll(filepath.Join(cfg.Repo, ".config", "agents", "skills-vendor", "herdr"), 0o755); err != nil {
		t.Fatal(err)
	}
	live := cfg.LiveSkillDirs[0]
	if err := os.MkdirAll(filepath.Join(live, "herdr"), 0o755); err != nil {
		t.Fatal(err)
	}

	found, _ := check(t, cfg, nil)
	msg := messages(found)
	if !strings.Contains(msg, "vendored なのに実ディレクトリ") {
		t.Errorf("検出しない: %q", msg)
	}
	if !strings.Contains(msg, "herdr") {
		t.Errorf("名前が出ていない: %q", msg)
	}
}

func TestResidueAcceptsVendoredSymlink(t *testing.T) {
	cfg := residueSetup(t)
	vendorDir := filepath.Join(cfg.Repo, ".config", "agents", "skills-vendor", "herdr")
	if err := os.MkdirAll(vendorDir, 0o755); err != nil {
		t.Fatal(err)
	}
	live := cfg.LiveSkillDirs[0]
	if err := os.MkdirAll(live, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(vendorDir, filepath.Join(live, "herdr")); err != nil {
		t.Fatal(err)
	}

	found, _ := check(t, cfg, nil)
	if len(found) != 0 {
		t.Errorf("正しい状態で検出した: %+v", found)
	}
}

func TestResidueAcceptsDeclaredTrustedSkill(t *testing.T) {
	cfg := residueSetup(t)
	if err := os.WriteFile(filepath.Join(cfg.Repo, "scripts", "setup", "claude-skills.txt"),
		[]byte("# 宣言\nanthropics/skills skill-creator\ngithub/awesome-copilot git-commit@v1.2.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	live := cfg.LiveSkillDirs[0]
	for _, n := range []string{"skill-creator", "git-commit"} {
		if err := os.MkdirAll(filepath.Join(live, n), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	found, _ := check(t, cfg, nil)
	if len(found) != 0 {
		t.Errorf("宣言済みの skill を報告した: %+v", found)
	}
}

func TestResidueGivesUpOnSkillsWhenDeclarationUnreadable(t *testing.T) {
	// **読めないまま「宣言に無い」と言うと、正しく入っているものまで
	// 残骸に見えてしまう。**
	cfg := residueSetup(t)
	if err := os.Remove(filepath.Join(cfg.Repo, "scripts", "setup", "claude-skills.txt")); err != nil {
		t.Fatal(err)
	}
	live := cfg.LiveSkillDirs[0]
	if err := os.MkdirAll(filepath.Join(live, "whatever"), 0o755); err != nil {
		t.Fatal(err)
	}

	found, notes := check(t, cfg, nil)
	if len(found) != 0 {
		t.Errorf("宣言が読めないのに報告した: %+v", found)
	}
	if len(notes) == 0 || !strings.Contains(notes[0], "skill の判定はしません") {
		t.Errorf("諦めた理由を出していない: %+v", notes)
	}
}

func TestResidueSkipsDotDirectories(t *testing.T) {
	// codex 同梱の .system 以下は宣言の対象外
	cfg := residueSetup(t)
	live := cfg.LiveSkillDirs[0]
	if err := os.MkdirAll(filepath.Join(live, ".system", "inner"), 0o755); err != nil {
		t.Fatal(err)
	}

	found, _ := check(t, cfg, nil)
	if len(found) != 0 {
		t.Errorf(". 始まりを報告した: %+v", found)
	}
}

func TestRenderResidueAlwaysExitsZero(t *testing.T) {
	// **見つかっても exit 0。** daily-update.sh から run_step_soft で呼ばれるので、
	// 非0を返すと毎日 FAILED 通知が飛び、やがて無視されるようになる
	var b bytes.Buffer
	code := RenderResidue(&b, []Residue{{"何か残っています", "撤去: rm -rf x"}}, nil)
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	out := b.String()
	if !strings.Contains(out, "  何か残っています") {
		t.Errorf("本文の字下げが違う: %q", out)
	}
	if !strings.Contains(out, "      撤去: rm -rf x") {
		t.Errorf("手順の字下げが違う: %q", out)
	}
	// 機械可読サマリ（呼び出し側はここから件数を取る）
	if !strings.Contains(out, "env-residue: FOUND=1") {
		t.Errorf("サマリ行が違う: %q", out)
	}
}

func TestRenderResidueSaysNothingFound(t *testing.T) {
	var b bytes.Buffer
	RenderResidue(&b, nil, nil)
	if !strings.Contains(b.String(), "残骸は見つかりませんでした") {
		t.Errorf("out = %q", b.String())
	}
	if !strings.Contains(b.String(), "env-residue: FOUND=0") {
		t.Errorf("out = %q", b.String())
	}
}

// --- migration ---

func TestRepoStateLineFormat(t *testing.T) {
	tests := []struct {
		name string
		s    RepoState
		want string
	}{
		{
			name: "remote あり",
			s:    RepoState{Path: "/r", Remotes: 1, Unpushed: 2, Stash: 1, Dirty: 3, Worktree: 0},
			want: "== /r  unpushed:2 stash:1 dirty:3 worktree:0",
		},
		{
			// **remote が無いのは push で逃がせない**ので明示する
			name: "remote なし",
			s:    RepoState{Path: "/r", Remotes: 0},
			want: "== /r  remote:なし unpushed:0 stash:0 dirty:0 worktree:0",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.s.Line(); got != tt.want {
				t.Errorf("got  %q\nwant %q", got, tt.want)
			}
		})
	}
}

func TestHasLocalWork(t *testing.T) {
	tests := []struct {
		name string
		s    RepoState
		want bool
	}{
		{"きれい", RepoState{Remotes: 1}, false},
		{"remote なし", RepoState{Remotes: 0}, true},
		{"未 push", RepoState{Remotes: 1, Unpushed: 1}, true},
		{"stash", RepoState{Remotes: 1, Stash: 1}, true},
		{"dirty", RepoState{Remotes: 1, Dirty: 1}, true},
		{"worktree", RepoState{Remotes: 1, Worktree: 1}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.s.HasLocalWork(); got != tt.want {
				t.Errorf("= %v, want %v", got, tt.want)
			}
		})
	}
}

func TestInspectRepoOnRealRepository(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	dir := t.TempDir()
	gitRun(t, dir, "init", "-q")
	gitRun(t, dir, "config", "user.email", "t@example.com")
	gitRun(t, dir, "config", "user.name", "t")
	if err := os.WriteFile(filepath.Join(dir, "a"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitRun(t, dir, "add", "-A")
	gitRun(t, dir, "commit", "-qm", "init")
	// 未追跡ファイルを置く（dirty に数える）
	if err := os.WriteFile(filepath.Join(dir, "untracked"), []byte("y"), 0o644); err != nil {
		t.Fatal(err)
	}

	s, ok := InspectRepo(context.Background(), execx.New(), dir)
	if !ok {
		t.Fatal("git リポジトリと認識しない")
	}
	if s.Remotes != 0 {
		t.Errorf("Remotes = %d, want 0", s.Remotes)
	}
	// **remote が無いので全コミットが未 push 扱い**
	if s.Unpushed != 1 {
		t.Errorf("Unpushed = %d, want 1", s.Unpushed)
	}
	if s.Dirty != 1 {
		t.Errorf("Dirty = %d, want 1（未追跡を含む）", s.Dirty)
	}
	if s.Worktree != 0 {
		t.Errorf("Worktree = %d, want 0（メインは数えない）", s.Worktree)
	}
	if !s.HasLocalWork() {
		t.Error("作業状態ありと判定しない")
	}
}

func TestInspectRepoRejectsNonRepo(t *testing.T) {
	if _, ok := InspectRepo(context.Background(), execx.New(), t.TempDir()); ok {
		t.Error("git リポジトリでないものを通した")
	}
}

func TestCheckMigrationExitCodes(t *testing.T) {
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	clean := t.TempDir()
	gitRun(t, clean, "init", "-q")
	gitRun(t, clean, "config", "user.email", "t@example.com")
	gitRun(t, clean, "config", "user.name", "t")
	gitRun(t, clean, "remote", "add", "origin", "https://example.invalid/r.git")

	var out, errOut bytes.Buffer
	code := CheckMigration(context.Background(), execx.New(), t.TempDir(),
		[]string{clean}, IO{Stdout: &out, Stderr: &errOut})
	if code != 0 {
		t.Errorf("きれいなリポジトリで exit = %d, want 0（%s）", code, out.String())
	}
	if !strings.Contains(out.String(), "0/1 リポジトリ") {
		t.Errorf("集計が違う: %q", out.String())
	}

	dirty := t.TempDir()
	gitRun(t, dirty, "init", "-q")
	out.Reset()
	code = CheckMigration(context.Background(), execx.New(), t.TempDir(),
		[]string{dirty}, IO{Stdout: &out, Stderr: &errOut})
	if code != 1 {
		t.Errorf("remote なしで exit = %d, want 1", code)
	}
	if !strings.Contains(out.String(), "remote:なし") {
		t.Errorf("remote なしを報告しない: %q", out.String())
	}
}

func TestCheckMigrationSkipsNonRepos(t *testing.T) {
	var out, errOut bytes.Buffer
	code := CheckMigration(context.Background(), execx.New(), t.TempDir(),
		[]string{t.TempDir(), t.TempDir()}, IO{Stdout: &out, Stderr: &errOut})
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out.String(), "0/0 リポジトリ") {
		t.Errorf("git でないものを数えている: %q", out.String())
	}
}

func TestListTargetsFailsWithoutGhqAndArgs(t *testing.T) {
	// **引数も ghq も無ければ何も点検できない。** 黙って0件成功にしない
	f := execx.NewFake().OnError("ghq", os.ErrNotExist)
	if _, err := ListTargets(context.Background(), f, t.TempDir(), nil); err == nil {
		t.Error("エラーを返さない")
	}
}

func TestListTargetsPrefersArgs(t *testing.T) {
	f := execx.NewFake()
	got, err := ListTargets(context.Background(), f, t.TempDir(), []string{"/a", "/b"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(got, ",") != "/a,/b" {
		t.Errorf("= %v", got)
	}
	if len(f.Calls) != 0 {
		t.Errorf("引数があるのに ghq を呼んだ: %v", f.Calls)
	}
}

func gitRun(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, b)
	}
}
