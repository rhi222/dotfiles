// skill vendoringは事前検査と人の承認なしにliveへ反映せず、metadataとsymlinkの整合を保つ。
// update時は差分を提示し、upstream欠落や未review状態を成功扱いしない。
package skill

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

func TestResolveOrigin(t *testing.T) {
	tests := []struct {
		in      string
		want    string
		wantErr bool
	}{
		{"anthropics/skills", "https://github.com/anthropics/skills.git", false},
		{"owner/repo/sub", "https://github.com/owner/repo/sub.git", false},
		{"https://github.com/o/r.git", "https://github.com/o/r.git", false},
		{"git@github.com:o/r.git", "git@github.com:o/r.git", false},
		{"ssh://git@host/o/r.git", "ssh://git@host/o/r.git", false},
		// **ローカルパスは素通しする。** テストが git init --bare した
		// ディレクトリを origin にする（ネットワークに出ないため）
		{"/tmp/local-bare.git", "/tmp/local-bare.git", false},
		{"./rel/path", "./rel/path", false},
		{"../up/path", "../up/path", false},
		// / を含まないものは owner/repo でも URL でもない
		{"justaword", "", true},
	}
	for _, tt := range tests {
		got, err := ResolveOrigin(tt.in)
		if tt.wantErr {
			if err == nil {
				t.Errorf("ResolveOrigin(%q) がエラーを返さない", tt.in)
			}
			continue
		}
		if err != nil {
			t.Errorf("ResolveOrigin(%q): %v", tt.in, err)
			continue
		}
		if got != tt.want {
			t.Errorf("ResolveOrigin(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestCachePathIsFilesystemSafe(t *testing.T) {
	// **スラッシュも __ に潰す。** 1階層のディレクトリ名にするので、
	// 実キャッシュは github.com__herdrdev__herdr のような名前になる
	// （Shell 版の sed 's|[^A-Za-z0-9._-]|__|g' と同じ）
	tests := []struct{ origin, want string }{
		{"https://github.com/o/r.git", "github.com__o__r"},
		{"git@github.com:o/r.git", "github.com__o__r"},
		{"http://host/o/r", "host__o__r"},
		{"/tmp/local bare.git", "__tmp__local__bare"},
	}
	for _, tt := range tests {
		got := CachePath("/cache", tt.origin)
		want := filepath.Join("/cache", tt.want)
		if got != want {
			t.Errorf("CachePath(%q) = %q, want %q", tt.origin, got, want)
		}
	}
}

func TestDetectLicense(t *testing.T) {
	tests := []struct {
		name, body, want string
	}{
		{"LICENSE", "MIT License\n\nCopyright...", "MIT"},
		{"LICENSE.md", "                    Apache License\n  Version 2.0", "Apache-2.0"},
		{"LICENSE.txt", "GNU GENERAL PUBLIC LICENSE", "GPL"},
		{"COPYING", "何か独自のライセンス", "unknown"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, tt.name), []byte(tt.body), 0o644); err != nil {
				t.Fatal(err)
			}
			if got := DetectLicense(dir); got != tt.want {
				t.Errorf("= %q, want %q", got, tt.want)
			}
		})
	}
	if got := DetectLicense(t.TempDir()); got != "none" {
		t.Errorf("ライセンスが無いとき = %q, want none", got)
	}
}

// --- preflight（取込前の門前払い） ---

func preflightSetup(t *testing.T) (cfg VendorConfig, src string) {
	t.Helper()
	base := t.TempDir()
	src = filepath.Join(base, "src")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "SKILL.md"), []byte("# skill\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return VendorConfig{
		VendorDir:  filepath.Join(base, "vendor"),
		CacheDir:   filepath.Join(base, "cache"),
		SelfSkills: filepath.Join(base, "self"),
		LiveDirs:   []string{filepath.Join(base, "live-claude"), filepath.Join(base, "live-agents")},
		Today:      "2026-01-02",
		AutoYes:    true,
	}, src
}

func TestPreflightRequiresSkillMd(t *testing.T) {
	cfg, src := preflightSetup(t)
	if err := os.Remove(filepath.Join(src, "SKILL.md")); err != nil {
		t.Fatal(err)
	}
	err := Preflight(cfg, src, "x")
	if err == nil || !strings.Contains(err.Error(), "SKILL.md") {
		t.Errorf("err = %v", err)
	}
}

func TestPreflightRejectsNameClashWithSelfSkill(t *testing.T) {
	// **自作 skill と名前が衝突すると、どちらが読まれるか分からなくなる。**
	cfg, src := preflightSetup(t)
	if err := os.MkdirAll(filepath.Join(cfg.SelfSkills, "dup"), 0o755); err != nil {
		t.Fatal(err)
	}
	err := Preflight(cfg, src, "dup")
	if err == nil || !strings.Contains(err.Error(), "名前が衝突") {
		t.Errorf("err = %v", err)
	}
}

func TestPreflightRejectsNameClashWithAgentSpecificSkill(t *testing.T) {
	cfg, src := preflightSetup(t)
	agentSpecific := filepath.Join(t.TempDir(), "codex-skills")
	cfg.AdditionalSelfSkills = []string{agentSpecific}
	if err := os.MkdirAll(filepath.Join(agentSpecific, "dup"), 0o755); err != nil {
		t.Fatal(err)
	}
	err := Preflight(cfg, src, "dup")
	if err == nil || !strings.Contains(err.Error(), "名前が衝突") {
		t.Errorf("err = %v", err)
	}
}

func TestPreflightRejectsRealDirInLive(t *testing.T) {
	// **gh skill が入れた実体が残っていると symlink が張れず、古い実体が
	// 読まれ続ける。** 取り込む前に気付けるようにする
	cfg, src := preflightSetup(t)
	if err := os.MkdirAll(filepath.Join(cfg.LiveDirs[0], "x"), 0o755); err != nil {
		t.Fatal(err)
	}
	err := Preflight(cfg, src, "x")
	if err == nil || !strings.Contains(err.Error(), "実ディレクトリ") {
		t.Fatalf("err = %v", err)
	}
	pe, ok := err.(*PreflightError)
	if !ok || !strings.Contains(pe.Detail, "rm -rf") {
		t.Errorf("復旧手順を案内していない: %+v", err)
	}
}

func TestPreflightAllowsSymlinkInLive(t *testing.T) {
	// 既に vendored への symlink が張られているのは正常な状態
	cfg, src := preflightSetup(t)
	if err := os.MkdirAll(cfg.LiveDirs[0], 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(src, filepath.Join(cfg.LiveDirs[0], "x")); err != nil {
		t.Fatal(err)
	}
	if err := Preflight(cfg, src, "x"); err != nil {
		t.Errorf("symlink を弾いてしまった: %v", err)
	}
}

func TestPreflightRejectsBinaryFiles(t *testing.T) {
	// **読んでレビューできないものは入れない。** 判定は audit と共有している
	cfg, src := preflightSetup(t)
	if err := os.WriteFile(filepath.Join(src, "blob.bin"), []byte{0x00, 0x01, 0x02}, 0o644); err != nil {
		t.Fatal(err)
	}
	err := Preflight(cfg, src, "x")
	if err == nil || !strings.Contains(err.Error(), "非テキストファイル") {
		t.Fatalf("err = %v", err)
	}
	pe := err.(*PreflightError)
	if !strings.Contains(pe.Detail, "blob.bin") {
		t.Errorf("どのファイルか出していない: %q", pe.Detail)
	}
}

func TestPreflightAllowsEmptyFiles(t *testing.T) {
	// 空ファイルは中身が無いので害がない
	cfg, src := preflightSetup(t)
	if err := os.WriteFile(filepath.Join(src, ".gitkeep"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Preflight(cfg, src, "x"); err != nil {
		t.Errorf("空ファイルを弾いてしまった: %v", err)
	}
}

// --- InstallFiles ---

func TestInstallFilesDropsGitAndExecBit(t *testing.T) {
	base := t.TempDir()
	src := filepath.Join(base, "src")
	dest := filepath.Join(base, "dest")
	mustWrite(t, filepath.Join(src, "SKILL.md"), "# s", 0o755) // 実行ビット付き
	mustWrite(t, filepath.Join(src, "sub", "a.md"), "a", 0o644)
	mustWrite(t, filepath.Join(src, ".git", "config"), "x", 0o644)

	if err := InstallFiles(src, dest); err != nil {
		t.Fatal(err)
	}

	st, err := os.Stat(filepath.Join(dest, "SKILL.md"))
	if err != nil {
		t.Fatal(err)
	}
	// **実行ビットを落とす。** skill は読まれるだけのもので実行される必要が無い
	if st.Mode().Perm()&0o111 != 0 {
		t.Errorf("実行ビットが残っている: %o", st.Mode().Perm())
	}
	if _, err := os.Stat(filepath.Join(dest, "sub", "a.md")); err != nil {
		t.Errorf("入れ子のファイルをコピーしていない: %v", err)
	}
	// **.git は持ち込まない**（upstream の履歴をリポジトリに混ぜない）
	if _, err := os.Stat(filepath.Join(dest, ".git")); err == nil {
		t.Error(".git を持ち込んでいる")
	}
}

func TestInstallFilesReplacesExistingContent(t *testing.T) {
	base := t.TempDir()
	src := filepath.Join(base, "src")
	dest := filepath.Join(base, "dest")
	mustWrite(t, filepath.Join(src, "new.md"), "new", 0o644)
	mustWrite(t, filepath.Join(dest, "stale.md"), "stale", 0o644)

	if err := InstallFiles(src, dest); err != nil {
		t.Fatal(err)
	}
	// **置き換えなので古いファイルは残らない**（upstream から消えたものを残さない）
	if _, err := os.Stat(filepath.Join(dest, "stale.md")); err == nil {
		t.Error("upstream から消えたファイルが残っている")
	}
}

// --- CopyLicense ---

func TestCopyLicenseTakesRepoRootWhenSkillHasNone(t *testing.T) {
	base := t.TempDir()
	clone := filepath.Join(base, "clone")
	src := filepath.Join(clone, "skills", "x")
	dest := filepath.Join(base, "dest")
	mustWrite(t, filepath.Join(clone, "LICENSE"), "MIT License", 0o644)
	mustWrite(t, filepath.Join(src, "SKILL.md"), "# s", 0o644)
	if err := os.MkdirAll(dest, 0o755); err != nil {
		t.Fatal(err)
	}

	var w bytes.Buffer
	CopyLicense(clone, src, dest, &w)

	b, err := os.ReadFile(filepath.Join(dest, "LICENSE"))
	if err != nil {
		t.Fatalf("リポジトリ直下から拾っていない: %v", err)
	}
	if string(b) != "MIT License" {
		t.Errorf("内容 = %q", b)
	}
}

func TestCopyLicenseWarnsWhenAbsent(t *testing.T) {
	base := t.TempDir()
	clone := filepath.Join(base, "clone")
	src := filepath.Join(clone, "s")
	dest := filepath.Join(base, "dest")
	mustWrite(t, filepath.Join(src, "SKILL.md"), "# s", 0o644)
	if err := os.MkdirAll(dest, 0o755); err != nil {
		t.Fatal(err)
	}

	var w bytes.Buffer
	CopyLicense(clone, src, dest, &w)
	if !strings.Contains(w.String(), "LICENSE が見つかりませんでした") {
		t.Errorf("警告を出していない: %q", w.String())
	}
}

// --- CheckLiveDirs ---

func TestCheckLiveDirsFlagsRealDirectory(t *testing.T) {
	// **これが status の穴だった。** .vendor.json は正しいのに gh 版の実体が
	// 残っていて、Claude は古い skill を読み続けていた（実際に6本）
	base := t.TempDir()
	vendorDir := filepath.Join(base, "vendor")
	live := filepath.Join(base, "live")
	mustWrite(t, filepath.Join(vendorDir, "x", "SKILL.md"), "# s", 0o644)
	if err := os.MkdirAll(filepath.Join(live, "x"), 0o755); err != nil {
		t.Fatal(err)
	}

	got := CheckLiveDirs([]string{live}, vendorDir, "x")
	if len(got) != 1 {
		t.Fatalf("件数 = %d, want 1: %+v", len(got), got)
	}
	if !strings.Contains(got[0].Problem, "実ディレクトリ") {
		t.Errorf("Problem = %q", got[0].Problem)
	}
	if got[0].Recovery == "" {
		t.Error("復旧手順が無い")
	}
}

func TestCheckLiveDirsFlagsSymlinkToWrongTarget(t *testing.T) {
	base := t.TempDir()
	vendorDir := filepath.Join(base, "vendor")
	live := filepath.Join(base, "live")
	other := filepath.Join(base, "other")
	mustWrite(t, filepath.Join(vendorDir, "x", "SKILL.md"), "# s", 0o644)
	mustWrite(t, filepath.Join(other, "SKILL.md"), "# other", 0o644)
	if err := os.MkdirAll(live, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, filepath.Join(live, "x")); err != nil {
		t.Fatal(err)
	}

	got := CheckLiveDirs([]string{live}, vendorDir, "x")
	if len(got) != 1 || !strings.Contains(got[0].Problem, "vendored を指していません") {
		t.Errorf("got = %+v", got)
	}
}

func TestCheckLiveDirsAcceptsCorrectSymlinkAndAbsence(t *testing.T) {
	// **無いことは異常ではない**（dotfilesLink.sh 未実行、その agent を
	// 使っていない端末）
	base := t.TempDir()
	vendorDir := filepath.Join(base, "vendor")
	live := filepath.Join(base, "live")
	absent := filepath.Join(base, "absent")
	mustWrite(t, filepath.Join(vendorDir, "x", "SKILL.md"), "# s", 0o644)
	if err := os.MkdirAll(live, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(vendorDir, "x"), filepath.Join(live, "x")); err != nil {
		t.Fatal(err)
	}

	if got := CheckLiveDirs([]string{live, absent}, vendorDir, "x"); len(got) != 0 {
		t.Errorf("正常な状態で問題を報告した: %+v", got)
	}
}

// --- add / update / status / list（実 git を使う） ---

func vendorEnv(t *testing.T) (cfg VendorConfig, bare string) {
	t.Helper()
	if testing.Short() {
		t.Skip("実 git リポジトリを作るので -short では飛ばす")
	}
	base := t.TempDir()

	// **ネットワークに出ない。** ローカルの bare リポジトリを origin にする
	work := filepath.Join(base, "work")
	mustWrite(t, filepath.Join(work, "skills", "demo", "SKILL.md"), "# demo skill\n本文\n", 0o644)
	mustWrite(t, filepath.Join(work, "LICENSE"), "MIT License\n", 0o644)
	gitRun(t, work, "init", "-q")
	gitRun(t, work, "config", "user.email", "t@example.com")
	gitRun(t, work, "config", "user.name", "t")
	gitRun(t, work, "add", "-A")
	gitRun(t, work, "commit", "-qm", "init")

	bare = filepath.Join(base, "origin.git")
	if out, err := exec.Command("git", "clone", "--quiet", "--bare", work, bare).CombinedOutput(); err != nil {
		t.Fatalf("bare clone: %v\n%s", err, out)
	}

	return VendorConfig{
		VendorDir:  filepath.Join(base, "vendor"),
		CacheDir:   filepath.Join(base, "cache"),
		SelfSkills: filepath.Join(base, "self"),
		LiveDirs:   []string{filepath.Join(base, "live")},
		Today:      "2026-01-02",
		AutoYes:    true,
	}, bare
}

func TestVendorAddInstallsAndWritesMeta(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}

	code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w)
	if code != 0 {
		t.Fatalf("exit = %d\nstdout:\n%s\nstderr:\n%s", code, out.String(), errOut.String())
	}

	dest := filepath.Join(cfg.VendorDir, "demo")
	if _, err := os.Stat(filepath.Join(dest, "SKILL.md")); err != nil {
		t.Errorf("SKILL.md が入っていない: %v", err)
	}
	// **upstream のライセンスを同梱する**（skill 直下に無いのでリポジトリ直下から）
	if _, err := os.Stat(filepath.Join(dest, "LICENSE")); err != nil {
		t.Errorf("LICENSE を同梱していない: %v", err)
	}

	meta, err := LoadMeta(filepath.Join(dest, ".vendor.json"))
	if err != nil {
		t.Fatal(err)
	}
	if meta.Origin != bare || meta.SubPath != "skills/demo" {
		t.Errorf("meta = %+v", meta)
	}
	// **取込時点では commit == reviewed_commit**（自分で読んで承認したので）
	if meta.Commit == "" || meta.Commit != meta.ReviewedCommit {
		t.Errorf("commit/reviewed = %q/%q", meta.Commit, meta.ReviewedCommit)
	}
	if meta.License != "MIT" {
		t.Errorf("License = %q, want MIT", meta.License)
	}
	if meta.VendoredAt != "2026-01-02" {
		t.Errorf("VendoredAt = %q", meta.VendoredAt)
	}
	// audit の findings は stderr へ出す（件数を読む側と混ざらないように）
	if !strings.Contains(errOut.String(), "findings") {
		t.Errorf("audit の結果を stderr に出していない: %q", errOut.String())
	}
}

func TestVendorAddAbortsWhenNotConfirmed(t *testing.T) {
	// **findings が 0 でも人の承認を要求する。** 平文の指示型 injection は
	// 正規表現では拾えないので、機械判定だけで通してはいけない
	cfg, bare := vendorEnv(t)
	cfg.AutoYes = false
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut, Confirm: func(string) bool { return false }}

	code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w)
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(out.String(), "取り込みを中止しました") {
		t.Errorf("stdout = %q", out.String())
	}
	// **1バイトも書かない**
	if _, err := os.Stat(filepath.Join(cfg.VendorDir, "demo")); err == nil {
		t.Error("承認していないのに取り込んだ")
	}
}

func TestVendorAddUsesExplicitName(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "renamed", w); code != 0 {
		t.Fatalf("exit = %d: %s", code, errOut.String())
	}
	if _, err := os.Stat(filepath.Join(cfg.VendorDir, "renamed", "SKILL.md")); err != nil {
		t.Errorf("指定した名前で入っていない: %v", err)
	}
}

func TestVendorUpdateNoChangeRefreshesCommitOnly(t *testing.T) {
	// **skill 以外の変更で upstream の HEAD が動いた場合。** ファイルが同じなら
	// レビューは要らないので commit と reviewed_commit だけを進める
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}
	before, _ := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))

	// skill 以外のファイルを変えて HEAD を進める
	clone := filepath.Join(t.TempDir(), "c")
	if o, err := exec.Command("git", "clone", "--quiet", bare, clone).CombinedOutput(); err != nil {
		t.Fatalf("clone: %v\n%s", err, o)
	}
	gitRun(t, clone, "config", "user.email", "t@example.com")
	gitRun(t, clone, "config", "user.name", "t")
	mustWrite(t, filepath.Join(clone, "README.md"), "unrelated\n", 0o644)
	gitRun(t, clone, "add", "-A")
	gitRun(t, clone, "commit", "-qm", "unrelated change")
	gitRun(t, clone, "push", "--quiet", "origin", "HEAD")

	out.Reset()
	errOut.Reset()
	if code := VendorUpdate(context.Background(), execx.New(), cfg, "demo", w); code != 0 {
		t.Fatalf("exit = %d\n%s\n%s", code, out.String(), errOut.String())
	}
	if !strings.Contains(out.String(), "変更なし") {
		t.Errorf("stdout = %q", out.String())
	}
	after, _ := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))
	if after.Commit == before.Commit {
		t.Error("commit を進めていない")
	}
	if after.Commit != after.ReviewedCommit {
		t.Error("reviewed_commit が追随していない")
	}
}

func TestVendorUpdateShowsDiffAndRequiresApproval(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}
	before, _ := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))

	// skill の中身を変える
	clone := filepath.Join(t.TempDir(), "c")
	if o, err := exec.Command("git", "clone", "--quiet", bare, clone).CombinedOutput(); err != nil {
		t.Fatalf("clone: %v\n%s", err, o)
	}
	gitRun(t, clone, "config", "user.email", "t@example.com")
	gitRun(t, clone, "config", "user.name", "t")
	mustWrite(t, filepath.Join(clone, "skills", "demo", "SKILL.md"), "# demo skill\n新しい本文\n", 0o644)
	gitRun(t, clone, "add", "-A")
	gitRun(t, clone, "commit", "-qm", "change skill")
	gitRun(t, clone, "push", "--quiet", "origin", "HEAD")

	// 承認しない -> 取り込まない
	out.Reset()
	errOut.Reset()
	deny := VendorIO{Stdout: &out, Stderr: &errOut, Confirm: func(string) bool { return false }}
	cfg.AutoYes = false
	if code := VendorUpdate(context.Background(), execx.New(), cfg, "demo", deny); code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(out.String(), "=== diff: demo") {
		t.Errorf("差分を見せていない: %q", out.String())
	}
	if !strings.Contains(out.String(), "新しい本文") {
		t.Errorf("差分の中身が出ていない: %q", out.String())
	}
	body, _ := os.ReadFile(filepath.Join(cfg.VendorDir, "demo", "SKILL.md"))
	if strings.Contains(string(body), "新しい本文") {
		t.Error("承認していないのに置き換えた")
	}
	unchanged, _ := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))
	if unchanged.Commit != before.Commit {
		t.Error("承認していないのに commit を進めた")
	}

	// 承認する -> 取り込む
	cfg.AutoYes = true
	out.Reset()
	errOut.Reset()
	if code := VendorUpdate(context.Background(), execx.New(), cfg, "demo", w); code != 0 {
		t.Fatalf("exit = %d\n%s", code, errOut.String())
	}
	body, _ = os.ReadFile(filepath.Join(cfg.VendorDir, "demo", "SKILL.md"))
	if !strings.Contains(string(body), "新しい本文") {
		t.Error("承認したのに置き換わっていない")
	}
}

func TestVendorUpdateFailsWhenSkillGoneUpstream(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}

	clone := filepath.Join(t.TempDir(), "c")
	if o, err := exec.Command("git", "clone", "--quiet", bare, clone).CombinedOutput(); err != nil {
		t.Fatalf("clone: %v\n%s", err, o)
	}
	gitRun(t, clone, "config", "user.email", "t@example.com")
	gitRun(t, clone, "config", "user.name", "t")
	gitRun(t, clone, "rm", "-rq", "skills/demo")
	gitRun(t, clone, "commit", "-qm", "remove skill")
	gitRun(t, clone, "push", "--quiet", "origin", "HEAD")

	errOut.Reset()
	if code := VendorUpdate(context.Background(), execx.New(), cfg, "demo", w); code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "消えています") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestVendorUpdateFailsForUnknownName(t *testing.T) {
	cfg, _ := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorUpdate(context.Background(), execx.New(), cfg, "nope", w); code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "見つかりません") {
		t.Errorf("stderr = %q", errOut.String())
	}
}

func TestVendorStatusDetectsUnreviewed(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}

	// commit だけ進めて reviewed_commit を置き去りにする
	jsonPath := filepath.Join(cfg.VendorDir, "demo", ".vendor.json")
	meta, _ := LoadMeta(jsonPath)
	meta.Commit = "0000000000000000000000000000000000000000"
	if err := SaveMeta(jsonPath, meta); err != nil {
		t.Fatal(err)
	}

	out.Reset()
	code := VendorStatus(context.Background(), execx.New(), cfg, true, w)
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(out.String(), "未レビュー") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestVendorStatusReportsOKWhenHealthy(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}

	out.Reset()
	// --no-network 相当（ls-remote を呼ばない）
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 0 {
		t.Errorf("exit = %d, want 0（%s）", code, out.String())
	}
	if !strings.Contains(out.String(), "[OK] demo") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestVendorStatusFlagsMissingMeta(t *testing.T) {
	cfg, _ := vendorEnv(t)
	if err := os.MkdirAll(filepath.Join(cfg.VendorDir, "orphan"), 0o755); err != nil {
		t.Fatal(err)
	}
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if !strings.Contains(out.String(), ".vendor.json が無い") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestVendorStatusSaysNothingWhenDirAbsent(t *testing.T) {
	cfg, _ := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if !strings.Contains(out.String(), "vendored skill はありません") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestVendorListShowsHeaderAndRows(t *testing.T) {
	cfg, bare := vendorEnv(t)
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("add failed: %s", errOut.String())
	}

	out.Reset()
	if code := VendorList(cfg, w); code != 0 {
		t.Errorf("exit = %d", code)
	}
	if !strings.Contains(out.String(), "NAME") || !strings.Contains(out.String(), "ORIGIN") {
		t.Errorf("見出しが無い: %q", out.String())
	}
	if !strings.Contains(out.String(), "demo") || !strings.Contains(out.String(), "MIT") {
		t.Errorf("行が出ていない: %q", out.String())
	}
}

func mustWrite(t *testing.T, path, body string, mode os.FileMode) {
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

func gitRun(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, b)
	}
}
