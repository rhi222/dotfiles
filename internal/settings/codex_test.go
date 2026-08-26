package settings

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCodexStatusMasksLocalStateAndFormatting(t *testing.T) {
	dir := t.TempDir()
	live := filepath.Join(dir, "config.toml")
	template := filepath.Join(dir, "config.example.toml")
	mustWriteCodex(t, live, `model = "gpt-5"
[projects."/private/path"]
trust_level = "trusted"
[notice]
hide_rate_limit_model_nudge = true
[tui]
status_line = ["model"]
model_availability_nux = { "gpt-5" = 1 }
[hooks.state."private-hook"]
trusted_hash = "secret-value"
`)
	mustWriteCodex(t, template, `# order and comments do not matter
[tui]
status_line = ["model"]
model = "ignored table member"
`)
	// 同じ意味に直す。table内へ置いたmodelは異なるキーなので、まず差分を確認する。
	var out bytes.Buffer
	got := CodexStatus(CodexConfig{Live: live, Template: template}, IO{Stdout: &out, Stderr: &out})
	if got != WouldWrite || !strings.Contains(out.String(), "tui.model") {
		t.Fatalf("unexpected first status: outcome=%v output=%q", got, out.String())
	}

	mustWriteCodex(t, template, `model="gpt-5"
[tui]
status_line=["model"]
`)
	out.Reset()
	got = CodexStatus(CodexConfig{Live: live, Template: template}, IO{Stdout: &out, Stderr: &out})
	if got != Unchanged {
		t.Fatalf("local state should be masked: outcome=%v output=%q", got, out.String())
	}
}

func TestCodexStatusReportsOnlyKeys(t *testing.T) {
	dir := t.TempDir()
	live := filepath.Join(dir, "live.toml")
	template := filepath.Join(dir, "template.toml")
	mustWriteCodex(t, live, `model = "private-live-value"`)
	mustWriteCodex(t, template, `model = "public-template-value"
personality = "friendly"
`)
	var out bytes.Buffer
	got := CodexStatus(CodexConfig{Live: live, Template: template}, IO{Stdout: &out, Stderr: &out})
	if got != WouldWrite {
		t.Fatalf("outcome=%v output=%q", got, out.String())
	}
	text := out.String()
	for _, want := range []string{"値が異なる: model", "実設定にない: personality"} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %q in %q", want, text)
		}
	}
	for _, secret := range []string{"private-live-value", "public-template-value", "friendly"} {
		if strings.Contains(text, secret) {
			t.Errorf("value leaked: %q in %q", secret, text)
		}
	}
}

func TestCodexStatusRejectsBrokenTOML(t *testing.T) {
	dir := t.TempDir()
	live := filepath.Join(dir, "live.toml")
	template := filepath.Join(dir, "template.toml")
	mustWriteCodex(t, live, `model = [`)
	mustWriteCodex(t, template, `model = "ok"`)
	var errOut bytes.Buffer
	if got := CodexStatus(CodexConfig{Live: live, Template: template}, IO{Stderr: &errOut}); got != Failed {
		t.Fatalf("outcome=%v output=%q", got, errOut.String())
	}
}

func mustWriteCodex(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
