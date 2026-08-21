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

// **Shell 版 skill-audit.sh との一致を実在の vendored skill で確かめる。**
// 監査は「何を HIGH と見なすか」の集合そのものなので、移植で取りこぼすと
// 検査が静かに弱くなる。合成ケースでは気付けないので実物で見る。
func TestAuditMatchesShellOnRealVendoredSkills(t *testing.T) {
	if testing.Short() {
		t.Skip("Shell 版を起動するので -short では飛ばす")
	}
	root := repoRoot(t)
	shellImpl := filepath.Join(root, "scripts", "skill-audit.sh")
	if _, err := os.Stat(shellImpl); err != nil {
		t.Skip("Shell 版が無い（wrapper 化済み）")
	}
	// wrapper になっていたら比較にならないので中身で判定する
	if b, err := os.ReadFile(shellImpl); err == nil && strings.Contains(string(b), "exec \"$DOTCTL\"") {
		t.Skip("Shell 版は wrapper なので比較しない")
	}

	vendorDir := filepath.Join(root, ".config", "claude", "skills-vendor")
	entries, err := os.ReadDir(vendorDir)
	if err != nil {
		t.Skip("vendored skill が無い")
	}

	checked := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(vendorDir, e.Name())
		t.Run(e.Name(), func(t *testing.T) {
			cmd := exec.Command("bash", shellImpl, dir)
			cmd.Dir = root
			shellOut, _ := cmd.CombinedOutput()

			res, aerr := Audit(context.Background(), execx.New(), dir)
			if aerr != nil {
				t.Fatal(aerr)
			}
			var buf bytes.Buffer
			RenderAudit(&buf, res, false)

			if buf.String() != string(shellOut) {
				t.Errorf("出力が違う\n--- shell ---\n%s\n--- go ---\n%s", shellOut, buf.String())
			}
		})
		checked++
	}
	if checked == 0 {
		t.Skip("比較できる skill が無かった")
	}
}

// 自作 skill でも一致すること（vendored とは書き方の癖が違う）。
func TestAuditMatchesShellOnSelfSkills(t *testing.T) {
	if testing.Short() {
		t.Skip("Shell 版を起動するので -short では飛ばす")
	}
	root := repoRoot(t)
	shellImpl := filepath.Join(root, "scripts", "skill-audit.sh")
	if b, err := os.ReadFile(shellImpl); err != nil || strings.Contains(string(b), "exec \"$DOTCTL\"") {
		t.Skip("Shell 版が無いか wrapper")
	}

	selfDir := filepath.Join(root, ".config", "claude", "skills")
	entries, err := os.ReadDir(selfDir)
	if err != nil {
		t.Skip("自作 skill が無い")
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(selfDir, e.Name())
		t.Run(e.Name(), func(t *testing.T) {
			cmd := exec.Command("bash", shellImpl, dir)
			cmd.Dir = root
			shellOut, _ := cmd.CombinedOutput()

			res, aerr := Audit(context.Background(), execx.New(), dir)
			if aerr != nil {
				t.Fatal(aerr)
			}
			var buf bytes.Buffer
			RenderAudit(&buf, res, false)
			if buf.String() != string(shellOut) {
				t.Errorf("出力が違う\n--- shell ---\n%s\n--- go ---\n%s", shellOut, buf.String())
			}
		})
	}
}

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Dir(filepath.Dir(wd))
}
