// 非テキストファイルは人が中身を確かめて --allow-binary で名指ししたときだけ
// 取り込み、その digest を記録する。差し替わったら status が落とす。
package skill

import (
	"bytes"
	"context"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/execx"
)

const testBinary = "\x00\x01png"

func TestPreflightAllowsNamedBinary(t *testing.T) {
	cfg, src := preflightSetup(t)
	mustWrite(t, filepath.Join(src, "assets", "logo.png"), testBinary, 0o644)
	cfg.AllowBinary = []string{"assets/logo.png"}
	if err := Preflight(cfg, src, "x"); err != nil {
		t.Errorf("名指ししたバイナリを弾いた: %v", err)
	}
}

func TestPreflightStillRejectsUnnamedBinary(t *testing.T) {
	cfg, src := preflightSetup(t)
	mustWrite(t, filepath.Join(src, "assets", "logo.png"), testBinary, 0o644)
	mustWrite(t, filepath.Join(src, "blob.bin"), testBinary, 0o644)
	cfg.AllowBinary = []string{"assets/logo.png"}
	err := Preflight(cfg, src, "x")
	if err == nil {
		t.Fatal("名指ししていないバイナリを通した")
	}
	pe := err.(*PreflightError)
	if !strings.Contains(pe.Detail, "blob.bin") || strings.Contains(pe.Detail, "logo.png") {
		t.Errorf("Detail = %q", pe.Detail)
	}
	// 確認済みのときの抜け道を案内する
	if !strings.Contains(pe.Detail, "--allow-binary") {
		t.Errorf("--allow-binary を案内していない: %q", pe.Detail)
	}
}

func TestPreflightRejectsAllowBinaryForMissingFile(t *testing.T) {
	// typo で名指ししたまま気付かないのを防ぐ
	cfg, src := preflightSetup(t)
	cfg.AllowBinary = []string{"assets/nope.png"}
	if err := Preflight(cfg, src, "x"); err == nil || !strings.Contains(err.Error(), "assets/nope.png") {
		t.Errorf("err = %v", err)
	}
}

// pushUpstream は bare に1ファイルの変更を push する。
func pushUpstream(t *testing.T, bare, rel, body string) {
	t.Helper()
	clone := filepath.Join(t.TempDir(), "c")
	if o, err := exec.Command("git", "clone", "--quiet", bare, clone).CombinedOutput(); err != nil {
		t.Fatalf("clone: %v\n%s", err, o)
	}
	gitRun(t, clone, "config", "user.email", "t@example.com")
	gitRun(t, clone, "config", "user.name", "t")
	mustWrite(t, filepath.Join(clone, rel), body, 0o644)
	gitRun(t, clone, "add", "-A")
	gitRun(t, clone, "commit", "-qm", "change "+rel)
	gitRun(t, clone, "push", "--quiet", "origin", "HEAD")
}

func addWithBinary(t *testing.T) (VendorConfig, string, VendorIO, *bytes.Buffer) {
	t.Helper()
	cfg, bare := vendorEnv(t)
	pushUpstream(t, bare, "skills/demo/assets/logo.png", testBinary)
	cfg.AllowBinary = []string{"assets/logo.png"}
	var out, errOut bytes.Buffer
	w := VendorIO{Stdout: &out, Stderr: &errOut}
	if code := VendorAdd(context.Background(), execx.New(), cfg, bare, "skills/demo", "", w); code != 0 {
		t.Fatalf("exit = %d\nstdout:\n%s\nstderr:\n%s", code, out.String(), errOut.String())
	}
	return cfg, bare, w, &out
}

func TestVendorAddRecordsBinaryDigest(t *testing.T) {
	cfg, _, _, out := addWithBinary(t)
	want, _ := FileSHA256(filepath.Join(cfg.VendorDir, "demo", "assets", "logo.png"))
	meta, err := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))
	if err != nil {
		t.Fatal(err)
	}
	if meta.BinarySHA256["assets/logo.png"] != want {
		t.Errorf("BinarySHA256 = %v, want %s", meta.BinarySHA256, want)
	}
	// 確認済みとして除いたので HIGH に数えない
	if meta.Audit.High != 0 {
		t.Errorf("Audit.High = %d", meta.Audit.High)
	}
	// 承認の前に、何を確認済みとして入れるかを見せる
	if !strings.Contains(out.String(), "assets/logo.png") || !strings.Contains(out.String(), want) {
		t.Errorf("バイナリと digest を見せていない: %q", out.String())
	}
}

func TestVendorStatusAcceptsReviewedBinaryAndFlagsReplaced(t *testing.T) {
	cfg, _, w, out := addWithBinary(t)
	out.Reset()
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 0 {
		t.Fatalf("exit = %d: %s", code, out.String())
	}

	mustWrite(t, filepath.Join(cfg.VendorDir, "demo", "assets", "logo.png"), "\x00swapped", 0o644)
	out.Reset()
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 1 {
		t.Errorf("差し替わったバイナリを通した: %s", out.String())
	}
	if !strings.Contains(out.String(), "HIGH") {
		t.Errorf("stdout = %q", out.String())
	}
}

func TestVendorUpdateRefreshesBinaryDigestAfterApproval(t *testing.T) {
	cfg, bare, w, _ := addWithBinary(t)
	cfg.AllowBinary = nil // update は .vendor.json の記録だけを根拠にする
	pushUpstream(t, bare, "skills/demo/assets/logo.png", "\x00new png")

	if code := VendorUpdate(context.Background(), execx.New(), cfg, "demo", w); code != 0 {
		t.Fatalf("exit = %d", code)
	}
	want, _ := FileSHA256(filepath.Join(cfg.VendorDir, "demo", "assets", "logo.png"))
	meta, _ := LoadMeta(filepath.Join(cfg.VendorDir, "demo", ".vendor.json"))
	if meta.BinarySHA256["assets/logo.png"] != want {
		t.Errorf("digest を更新していない: %v", meta.BinarySHA256)
	}
	if code := VendorStatus(context.Background(), execx.New(), cfg, true, w); code != 0 {
		t.Error("update 後の status が落ちる")
	}
}
