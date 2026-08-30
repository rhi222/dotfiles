package pluginvendor

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/skill"
)

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func testMeta() Meta {
	return Meta{
		Origin:         "https://example.com/plugin.git",
		Commit:         "abcdef0123456789",
		ReviewedCommit: "abcdef0123456789",
		VendoredAt:     "2026-08-31",
		Version:        "1.2.3",
		Files: []string{
			".claude-plugin/plugin.json",
			".codex-plugin/plugin.json",
			"hooks/claude-codex-hooks.json",
			"skills/demo/SKILL.md",
		},
		GeneratedFiles: []string{"hooks/hooks.json"},
		BinarySHA256:   map[string]string{},
		Audit:          skill.AuditCount{},
		License:        "MIT",
	}
}

func writeTestManifests(t *testing.T, dir string) {
	t.Helper()
	manifest := `{"version":"1.2.3+vendor.abcdef0"}`
	write(t, filepath.Join(dir, ".claude-plugin/plugin.json"), manifest)
	write(t, filepath.Join(dir, ".codex-plugin/plugin.json"), manifest)
}

func TestBuildCandidatePinsVersionAndUsesDefaultCodexHookPath(t *testing.T) {
	clone := t.TempDir()
	dest := t.TempDir()
	manifest := `{"name":"ponytail","version":"2.0.0","description":"x","author":{"name":"x"},"hooks":"./hooks/claude-codex-hooks.json","skills":"./skills/","interface":{"displayName":"Ponytail","shortDescription":"x","longDescription":"x","developerName":"x","category":"Productivity","capabilities":[]}}`
	write(t, filepath.Join(clone, ".claude-plugin/plugin.json"), manifest)
	write(t, filepath.Join(clone, ".codex-plugin/plugin.json"), manifest)
	write(t, filepath.Join(clone, "hooks/claude-codex-hooks.json"), `{"hooks":{}}`)
	write(t, filepath.Join(clone, "skills/demo/SKILL.md"), "---\nname: demo\ndescription: demo\n---\n")

	meta := testMeta()
	if err := buildCandidate(clone, dest, "1234567890abcdef", meta); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(dest, ".codex-plugin/plugin.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	if got["version"] != "2.0.0+vendor.1234567" {
		t.Fatalf("version = %v", got["version"])
	}
	if _, ok := got["hooks"]; ok {
		t.Fatal("Codex manifestにvalidator非対応のhooks fieldが残っている")
	}
	if _, err := os.Stat(filepath.Join(dest, "hooks/hooks.json")); err != nil {
		t.Fatal("Codexのdefault hook pathが無い")
	}
}

func TestStatusAcceptsReviewedBinaryDigest(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "demo")
	writeTestManifests(t, dir)
	write(t, filepath.Join(dir, "payload.bin"), "\x00payload")
	hash, err := fileSHA256(filepath.Join(dir, "payload.bin"))
	if err != nil {
		t.Fatal(err)
	}
	meta := testMeta()
	meta.Files = []string{".claude-plugin/plugin.json", ".codex-plugin/plugin.json", "payload.bin"}
	meta.GeneratedFiles = nil
	meta.BinarySHA256 = map[string]string{"payload.bin": hash}
	if err := saveMeta(filepath.Join(dir, ".vendor.json"), meta); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	code := Status(context.Background(), nil, Config{VendorDir: root}, true, IO{Stdout: &out})
	if code != 0 || !strings.Contains(out.String(), "[OK] demo") {
		t.Fatalf("code=%d out=%q", code, out.String())
	}
}

func TestStatusRejectsChangedReviewedBinary(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "demo")
	writeTestManifests(t, dir)
	write(t, filepath.Join(dir, "payload.bin"), "\x00changed")
	meta := testMeta()
	meta.Files = []string{".claude-plugin/plugin.json", ".codex-plugin/plugin.json", "payload.bin"}
	meta.GeneratedFiles = nil
	meta.BinarySHA256 = map[string]string{"payload.bin": "deadbeef"}
	if err := saveMeta(filepath.Join(dir, ".vendor.json"), meta); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	code := Status(context.Background(), nil, Config{VendorDir: root}, true, IO{Stdout: &out})
	if code == 0 || !strings.Contains(out.String(), "audit結果が記録と違う") {
		t.Fatalf("code=%d out=%q", code, out.String())
	}
}

func TestStatusRejectsInvalidJSONAndManifestVersion(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "demo")
	meta := testMeta()
	write(t, filepath.Join(dir, ".claude-plugin/plugin.json"), `{"version":"9.9.9"}`)
	write(t, filepath.Join(dir, ".codex-plugin/plugin.json"), `{broken`)
	write(t, filepath.Join(dir, "hooks/claude-codex-hooks.json"), `{"hooks":{}}`)
	write(t, filepath.Join(dir, "skills/demo/SKILL.md"), "---\nname: demo\ndescription: demo\n---\n")
	write(t, filepath.Join(dir, "hooks/hooks.json"), `{"hooks":{}}`)
	if err := saveMeta(filepath.Join(dir, ".vendor.json"), meta); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	code := Status(context.Background(), nil, Config{VendorDir: root}, true, IO{Stdout: &out})
	if code == 0 || !strings.Contains(out.String(), "不正なJSON") || !strings.Contains(out.String(), "manifest version") {
		t.Fatalf("code=%d out=%q", code, out.String())
	}
}
