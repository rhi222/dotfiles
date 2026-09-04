// private bundleはdry-runで変更せず、adopt時も既存内容を失わずsymlinkと権限を整える。
// export/importは壊れた入力や競合を拒否し、明示的なforceなしに上書きしない。
package privatebundle

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

// 分類は純粋関数。**リンク切れを最初に見る**ことが要点で、実体が消えたうえに
// dangling symlink が残っている状態は「集約先に無い」にも当てはまるが、
// 手を打つ必要があるのはリンク切れのほう。
func TestClassify(t *testing.T) {
	tests := []struct {
		name                           string
		isSymlink, resolves, dstExists bool
		want                           StatusKind
	}{
		{"正常にリンクされている", true, true, true, Linked},
		{"実体があるが未リンク", false, false, true, Unlinked},
		{"集約先に無い", false, false, false, Absent},
		{"リンク切れ", true, false, false, Broken},
		{"リンク切れ（集約先はあるが辿れない）", true, false, true, Broken},
		{"リンクが無く集約先も無い", false, false, false, Absent},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Classify(tt.isSymlink, tt.resolves, tt.dstExists); got != tt.want {
				t.Errorf("= %v, want %v", got, tt.want)
			}
		})
	}
}

func TestEntriesDeclarationIsSane(t *testing.T) {
	// **宣言はこのパッケージだけが持つ。** 重複や空が混ざると
	// adopt が同じものを2回動かす
	seen := map[string]bool{}
	for _, e := range Entries {
		key := e.Kind.String() + ":" + e.Rel
		if e.Rel == "" {
			t.Error("空の Rel がある")
		}
		if seen[key] {
			t.Errorf("重複した宣言: %s", key)
		}
		seen[key] = true
		if strings.HasPrefix(e.Rel, "/") {
			t.Errorf("絶対パスの宣言: %s", e.Rel)
		}
	}
	// passwords/ は @under（子の名前が端末ごとに違う）
	found := false
	for _, e := range Entries {
		if strings.HasSuffix(e.Rel, "passwords") && e.Under {
			found = true
		}
	}
	if !found {
		t.Error("passwords が @under で宣言されていない")
	}
}

func TestBootstrapDocumentsEntries(t *testing.T) {
	// パス一覧は復旧契約。Entries に追加した機密ファイルが手動移行の台帳から
	// 抜けても動作テストでは見つからないため、文言ではなくパスだけを固定する。
	doc, err := os.ReadFile("../../docs/bootstrap.md")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range Entries {
		if !bytes.Contains(doc, []byte(e.Rel)) {
			t.Errorf("bootstrap.md に移植対象が無い: %s", e.Rel)
		}
	}
}

func setup(t *testing.T) Config {
	t.Helper()
	base := t.TempDir()
	cfg := Config{
		PrivateDir: filepath.Join(base, "private"),
		Home:       filepath.Join(base, "home"),
		RepoDir:    filepath.Join(base, "repo"),
		Today:      "2026-01-02",
	}
	for _, d := range []string{cfg.Home, cfg.RepoDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// git リポジトリにしておく（check-ignore を使うため）
	gitRun(t, cfg.RepoDir, "init", "-q")
	gitRun(t, cfg.RepoDir, "config", "user.email", "t@example.com")
	gitRun(t, cfg.RepoDir, "config", "user.name", "t")
	return cfg
}

func TestAdoptDryRunTouchesNothing(t *testing.T) {
	cfg := setup(t)
	target := filepath.Join(cfg.Home, ".claude", "local-context.md")
	mustWrite(t, target, "secret", 0o600)

	var out, errOut bytes.Buffer
	w := IO{Stdout: &out, Stderr: &errOut}
	if rc := Adopt(context.Background(), execx.New(), cfg, false, w); rc != 0 {
		t.Fatalf("rc = %d: %s", rc, errOut.String())
	}
	if !strings.Contains(out.String(), "[DRY-RUN]") {
		t.Errorf("dry-run の表示が無い: %q", out.String())
	}
	if !strings.Contains(out.String(), "--execute を付けて") {
		t.Errorf("実行方法を案内していない: %q", out.String())
	}
	// **1バイトも動かさない**
	if fi, err := os.Lstat(target); err != nil || fi.Mode()&os.ModeSymlink != 0 {
		t.Error("dry-run なのに実体を動かした")
	}
	if _, err := os.Stat(cfg.PrivateDir); err == nil {
		t.Error("dry-run なのに集約先を作った")
	}
}

func TestAdoptMovesAndLinks(t *testing.T) {
	cfg := setup(t)
	target := filepath.Join(cfg.Home, ".claude", "local-context.md")
	mustWrite(t, target, "secret", 0o600)

	var out, errOut bytes.Buffer
	w := IO{Stdout: &out, Stderr: &errOut}
	if rc := Adopt(context.Background(), execx.New(), cfg, true, w); rc != 0 {
		t.Fatalf("rc = %d: %s", rc, errOut.String())
	}

	// 元の場所は symlink になる
	fi, err := os.Lstat(target)
	if err != nil || fi.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("元の場所が symlink になっていない: %v", err)
	}
	// 実体は集約先に移る
	moved := filepath.Join(cfg.PrivateDir, "home", ".claude", "local-context.md")
	body, err := os.ReadFile(moved)
	if err != nil || string(body) != "secret" {
		t.Errorf("集約先に実体が無い: %v %q", err, body)
	}
	// symlink 経由で読める
	viaLink, err := os.ReadFile(target)
	if err != nil || string(viaLink) != "secret" {
		t.Errorf("symlink 経由で読めない: %v", err)
	}
	if !strings.Contains(out.String(), "移動: 1 件") {
		t.Errorf("集計が違う: %q", out.String())
	}
}

func TestAdoptHardensPermissions(t *testing.T) {
	// **集約先は資格情報を1箇所に集めたディレクトリなので、作った直後に締める。**
	// import 側だけでハードニングすると、集約した端末では 755 のまま残る
	cfg := setup(t)
	mustWrite(t, filepath.Join(cfg.Home, ".config", "linear", "api-key"), "key", 0o644)

	var out, errOut bytes.Buffer
	if rc := Adopt(context.Background(), execx.New(), cfg, true, IO{Stdout: &out, Stderr: &errOut}); rc != 0 {
		t.Fatalf("rc = %d: %s", rc, errOut.String())
	}

	st, err := os.Stat(cfg.PrivateDir)
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Mode().Perm(); got != 0o700 {
		t.Errorf("集約先の権限 = %o, want 700", got)
	}
	fst, err := os.Stat(filepath.Join(cfg.PrivateDir, "home", ".config", "linear", "api-key"))
	if err != nil {
		t.Fatal(err)
	}
	if got := fst.Mode().Perm(); got != 0o600 {
		t.Errorf("ファイルの権限 = %o, want 600", got)
	}
}

func TestAdoptSkipsExistingSymlinkAndReportsMissing(t *testing.T) {
	cfg := setup(t)
	// 既に symlink になっているもの
	linked := filepath.Join(cfg.Home, ".claude", "local-context.md")
	real := filepath.Join(cfg.PrivateDir, "home", ".claude", "local-context.md")
	mustWrite(t, real, "x", 0o600)
	if err := os.MkdirAll(filepath.Dir(linked), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, linked); err != nil {
		t.Fatal(err)
	}

	var out, errOut bytes.Buffer
	if rc := Adopt(context.Background(), execx.New(), cfg, true, IO{Stdout: &out, Stderr: &errOut}); rc != 0 {
		t.Fatalf("rc = %d: %s", rc, errOut.String())
	}
	if !strings.Contains(out.String(), "[SKIP]") {
		t.Errorf("既存 symlink を SKIP していない: %q", out.String())
	}
	// **無いものは異常ではない**（この端末で使っていないだけ）
	if !strings.Contains(out.String(), "[MISS]") {
		t.Errorf("不在を報告していない: %q", out.String())
	}
	if !strings.Contains(out.String(), "既に symlink: 1 件") {
		t.Errorf("集計が違う: %q", out.String())
	}
}

func TestAdoptPicksIgnoredChildrenOnly(t *testing.T) {
	// **passwords/ は README.md が追跡対象で中身だけが ignore される。**
	// 追跡ファイルを巻き込むとリポジトリから消える
	cfg := setup(t)
	pw := filepath.Join(cfg.RepoDir, ".config", "AutoHotkey", "ahk-snippets", "passwords")
	mustWrite(t, filepath.Join(pw, "README.md"), "説明", 0o644)
	mustWrite(t, filepath.Join(pw, "secret-a.ahk"), "秘密", 0o600)
	mustWrite(t, filepath.Join(cfg.RepoDir, ".gitignore"),
		".config/AutoHotkey/ahk-snippets/passwords/*\n!.config/AutoHotkey/ahk-snippets/passwords/README.md\n", 0o644)
	gitRun(t, cfg.RepoDir, "add", "-A")
	gitRun(t, cfg.RepoDir, "commit", "-qm", "init")

	var out, errOut bytes.Buffer
	if rc := Adopt(context.Background(), execx.New(), cfg, true, IO{Stdout: &out, Stderr: &errOut}); rc != 0 {
		t.Fatalf("rc = %d: %s", rc, errOut.String())
	}

	// ignore されている方は移る
	if _, err := os.Stat(filepath.Join(cfg.PrivateDir, "repo",
		".config/AutoHotkey/ahk-snippets/passwords/secret-a.ahk")); err != nil {
		t.Errorf("ignore された子を移していない: %v", err)
	}
	// 追跡ファイルは触らない
	fi, err := os.Lstat(filepath.Join(pw, "README.md"))
	if err != nil || fi.Mode()&os.ModeSymlink != 0 {
		t.Error("追跡ファイルを動かした")
	}
}

// --- export / import（実 zip を使う） ---

func TestExportImportRoundTrip(t *testing.T) {
	if testing.Short() {
		t.Skip("zip/unzip を起動するので -short では飛ばす")
	}
	requireCmd(t, "zip")
	requireCmd(t, "unzip")

	cfg := setup(t)
	cfg.ZipPassword = "testpass"
	mustWrite(t, filepath.Join(cfg.PrivateDir, "home", ".config", "linear", "api-key"), "KEY", 0o600)
	mustWrite(t, filepath.Join(cfg.PrivateDir, "repo", "note.txt"), "メモ", 0o644)

	out := filepath.Join(t.TempDir(), "bundle.zip")
	var o, e bytes.Buffer
	if rc := Export(context.Background(), execx.New(), cfg, out, IO{Stdout: &o, Stderr: &e}); rc != 0 {
		t.Fatalf("export rc = %d: %s", rc, e.String())
	}
	st, err := os.Stat(out)
	if err != nil {
		t.Fatal(err)
	}
	// **zip 自体も 600。** 資格情報の塊なので緩めない
	if got := st.Mode().Perm(); got != 0o600 {
		t.Errorf("zip の権限 = %o, want 600", got)
	}

	// 別の集約先へ展開する
	cfg2 := cfg
	cfg2.PrivateDir = filepath.Join(t.TempDir(), "restored")
	o.Reset()
	e.Reset()
	if rc := Import(context.Background(), execx.New(), cfg2, out, false, IO{Stdout: &o, Stderr: &e}); rc != 0 {
		t.Fatalf("import rc = %d: %s", rc, e.String())
	}
	body, err := os.ReadFile(filepath.Join(cfg2.PrivateDir, "home", ".config", "linear", "api-key"))
	if err != nil || string(body) != "KEY" {
		t.Errorf("復元できていない: %v %q", err, body)
	}
	// **パーミッションは zip の保存内容に頼らず張り直す**
	fst, err := os.Stat(filepath.Join(cfg2.PrivateDir, "repo", "note.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if got := fst.Mode().Perm(); got != 0o600 {
		t.Errorf("展開後の権限 = %o, want 600", got)
	}
}

func TestExportKeepsSymlinksAsSymlinks(t *testing.T) {
	// **-y が無いと symlink を辿って実体化し、repos.yml が2つになる。**
	// 実体化しても「中身が読める」テストは通ってしまうので、symlink であること
	// 自体を検査する
	if testing.Short() {
		t.Skip("zip/unzip を起動するので -short では飛ばす")
	}
	requireCmd(t, "zip")
	requireCmd(t, "unzip")

	cfg := setup(t)
	cfg.ZipPassword = "testpass"
	realFile := filepath.Join(cfg.PrivateDir, "repo", "real.yml")
	mustWrite(t, realFile, "a: 1\n", 0o600)
	link := filepath.Join(cfg.PrivateDir, "repo", "linked.yml")
	if err := os.Symlink("real.yml", link); err != nil {
		t.Fatal(err)
	}

	out := filepath.Join(t.TempDir(), "b.zip")
	var o, e bytes.Buffer
	if rc := Export(context.Background(), execx.New(), cfg, out, IO{Stdout: &o, Stderr: &e}); rc != 0 {
		t.Fatalf("export rc = %d: %s", rc, e.String())
	}

	cfg2 := cfg
	cfg2.PrivateDir = filepath.Join(t.TempDir(), "restored")
	if rc := Import(context.Background(), execx.New(), cfg2, out, false, IO{Stdout: &o, Stderr: &e}); rc != 0 {
		t.Fatalf("import rc = %d: %s", rc, e.String())
	}

	fi, err := os.Lstat(filepath.Join(cfg2.PrivateDir, "repo", "linked.yml"))
	if err != nil {
		t.Fatal(err)
	}
	if fi.Mode()&os.ModeSymlink == 0 {
		t.Error("symlink が実体化している（zip -y が効いていない）")
	}
}

func TestExportFailsWhenPrivateDirMissing(t *testing.T) {
	cfg := setup(t)
	var o, e bytes.Buffer
	if rc := Export(context.Background(), execx.New(), cfg, filepath.Join(t.TempDir(), "x.zip"),
		IO{Stdout: &o, Stderr: &e}); rc != 1 {
		t.Errorf("rc = %d, want 1", rc)
	}
	if !strings.Contains(e.String(), "adopt --execute") {
		t.Errorf("次の手を案内していない: %q", e.String())
	}
}

func TestExportRefusesToOverwrite(t *testing.T) {
	if testing.Short() {
		t.Skip("zip を起動するので -short では飛ばす")
	}
	requireCmd(t, "zip")
	cfg := setup(t)
	cfg.ZipPassword = "p"
	mustWrite(t, filepath.Join(cfg.PrivateDir, "repo", "a"), "x", 0o600)

	out := filepath.Join(t.TempDir(), "b.zip")
	mustWrite(t, out, "既存", 0o600)

	var o, e bytes.Buffer
	if rc := Export(context.Background(), execx.New(), cfg, out, IO{Stdout: &o, Stderr: &e}); rc != 1 {
		t.Errorf("rc = %d, want 1", rc)
	}
	body, _ := os.ReadFile(out)
	if string(body) != "既存" {
		t.Error("既存ファイルを壊した")
	}
}

func TestImportRefusesExistingDirWithoutForce(t *testing.T) {
	cfg := setup(t)
	mustWrite(t, filepath.Join(cfg.PrivateDir, "keep.txt"), "残す", 0o600)
	zipfile := filepath.Join(t.TempDir(), "b.zip")
	mustWrite(t, zipfile, "dummy", 0o600)

	var o, e bytes.Buffer
	if rc := Import(context.Background(), execx.New(), cfg, zipfile, false, IO{Stdout: &o, Stderr: &e}); rc != 1 {
		t.Errorf("rc = %d, want 1", rc)
	}
	if !strings.Contains(e.String(), "--force") {
		t.Errorf("--force を案内していない: %q", e.String())
	}
	if _, err := os.Stat(filepath.Join(cfg.PrivateDir, "keep.txt")); err != nil {
		t.Error("既存の集約先を壊した")
	}
}

func TestImportFailsWhenZipMissing(t *testing.T) {
	cfg := setup(t)
	var o, e bytes.Buffer
	if rc := Import(context.Background(), execx.New(), cfg,
		filepath.Join(t.TempDir(), "nope.zip"), false, IO{Stdout: &o, Stderr: &e}); rc != 1 {
		t.Errorf("rc = %d, want 1", rc)
	}
	if !strings.Contains(e.String(), "zip がありません") {
		t.Errorf("stderr = %q", e.String())
	}
}

// --- status ---

func TestStatusGroupsByState(t *testing.T) {
	cfg := setup(t)
	// リンク済み
	real1 := filepath.Join(cfg.PrivateDir, "home", ".claude", "local-context.md")
	mustWrite(t, real1, "x", 0o600)
	src1 := filepath.Join(cfg.Home, ".claude", "local-context.md")
	if err := os.MkdirAll(filepath.Dir(src1), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real1, src1); err != nil {
		t.Fatal(err)
	}
	// 未リンク（実体が両方にある）
	mustWrite(t, filepath.Join(cfg.PrivateDir, "repo", ".config/git/config-local"), "y", 0o600)
	mustWrite(t, filepath.Join(cfg.RepoDir, ".config/git/config-local"), "y", 0o600)
	// リンク切れ
	src3 := filepath.Join(cfg.RepoDir, ".config/git/config-work")
	if err := os.MkdirAll(filepath.Dir(src3), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(cfg.PrivateDir, "repo", ".config/git/config-work"), src3); err != nil {
		t.Fatal(err)
	}

	var out, errOut bytes.Buffer
	if rc := Status(context.Background(), execx.New(), cfg, IO{Stdout: &out, Stderr: &errOut}); rc != 0 {
		t.Fatalf("rc = %d", rc)
	}
	s := out.String()
	for _, want := range []string{
		"集約先: " + cfg.PrivateDir,
		"リンク済み (1)",
		"未リンク (1)  ← ./dotfilesLink.sh を実行してください",
		"リンク切れ (1)  ← 集約先から実体が消えています",
		"集約先に無い (",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("出力に %q が無い:\n%s", want, s)
		}
	}
}

func TestStatusFallsBackWhenPrivateDirMissing(t *testing.T) {
	// **無いこと自体は異常ではない。** 旧環境が無い立ち上げでは雛形生成に落ちる
	cfg := setup(t)
	var out, errOut bytes.Buffer
	if rc := Status(context.Background(), execx.New(), cfg, IO{Stdout: &out, Stderr: &errOut}); rc != 0 {
		t.Errorf("rc = %d, want 0", rc)
	}
	if !strings.Contains(out.String(), "雛形生成にフォールバック") {
		t.Errorf("フォールバックを案内していない: %q", out.String())
	}
}

// --- HardenPermissions ---

func TestHardenPermissionsDoesNotFollowSymlinks(t *testing.T) {
	// **os.Chmod は symlink を辿る。** 辿ると集約先の外の実体の権限まで変える
	base := t.TempDir()
	dir := filepath.Join(base, "private")
	outside := filepath.Join(base, "outside.txt")
	mustWrite(t, outside, "外の実体", 0o644)
	mustWrite(t, filepath.Join(dir, "inside.txt"), "中の実体", 0o644)
	if err := os.Symlink(outside, filepath.Join(dir, "link.txt")); err != nil {
		t.Fatal(err)
	}

	if err := HardenPermissions(dir); err != nil {
		t.Fatal(err)
	}

	inside, _ := os.Stat(filepath.Join(dir, "inside.txt"))
	if got := inside.Mode().Perm(); got != 0o600 {
		t.Errorf("中の実体 = %o, want 600", got)
	}
	out, _ := os.Stat(outside)
	if got := out.Mode().Perm(); got != 0o644 {
		t.Errorf("symlink を辿って外の実体を変えた: %o", got)
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

func requireCmd(t *testing.T, name string) {
	t.Helper()
	if _, err := exec.LookPath(name); err != nil {
		t.Skipf("%s が無い", name)
	}
}
