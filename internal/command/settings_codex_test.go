package command

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rhi222/dotfiles/internal/settings"
)

func TestRunSettingsCodexStatus(t *testing.T) {
	dir := t.TempDir()
	live := filepath.Join(dir, "live.toml")
	template := filepath.Join(dir, "template.toml")
	for _, path := range []string{live, template} {
		if err := os.WriteFile(path, []byte(`model = "gpt-5"`), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	var stdout, stderr bytes.Buffer
	env := Env{
		Stdout: &stdout,
		Stderr: &stderr,
		CodexSettings: settings.CodexConfig{
			Live:     live,
			Template: template,
		},
	}
	if got := runSettings(context.Background(), []string{"sync", "codex", "status"}, env); got != 0 {
		t.Fatalf("exit=%d stderr=%q", got, stderr.String())
	}
	if !strings.Contains(stdout.String(), "一致") {
		t.Fatalf("stdout=%q", stdout.String())
	}
}

func TestRunSettingsCodexRejectsWriteActions(t *testing.T) {
	var stdout, stderr bytes.Buffer
	env := Env{Stdout: &stdout, Stderr: &stderr}
	if got := runSettings(context.Background(), []string{"sync", "codex", "push"}, env); got != 2 {
		t.Fatalf("exit=%d stderr=%q", got, stderr.String())
	}
}
