// Docker の起動時通知は、表示とキャッシュ更新要否を1回の CLI 呼び出しで返す。
// dotctl を2回呼ぶと version skew 警告も2回出るため、終了コードを更新要否に使う。
package command

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/rhi222/dotfiles/internal/docker"
)

func TestDockerNoticeSignalsRefreshWithoutCache(t *testing.T) {
	cfg := docker.DefaultConfig(t.TempDir())
	cfg.Now = time.Unix(1_700_000_000, 0)

	code, out, errOut := runEnv(t, Env{Docker: cfg}, "docker", "notice")
	if code != 0 {
		t.Errorf("cache 無しは refresh 必要: exit = %d", code)
	}
	if out != "" || errOut != "" {
		t.Errorf("cache 無しでは通知しない: stdout=%q stderr=%q", out, errOut)
	}
}

func TestDockerNoticePrintsNoticeAndSignalsFreshness(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	tests := []struct {
		name        string
		generatedAt int64
		wantCode    int
	}{
		{"fresh なら更新不要", now.Add(-time.Minute).Unix(), 1},
		{"stale なら更新必要", now.Add(-7 * time.Hour).Unix(), 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := docker.DefaultConfig(t.TempDir())
			cfg.Now = now
			cfg.CacheFile = filepath.Join(t.TempDir(), "stats.json")
			writeDockerNoticeCache(t, cfg.CacheFile, docker.Stats{
				GeneratedAt: tt.generatedAt,
				Schema:      docker.SchemaCurrent,
				DF: []docker.DFEntry{
					{Type: "Containers", Reclaimable: "6GB"},
				},
			})

			code, out, errOut := runEnv(t, Env{Docker: cfg}, "docker", "notice")
			if code != tt.wantCode {
				t.Errorf("exit = %d, want %d", code, tt.wantCode)
			}
			if out == "" {
				t.Error("通知が stdout に出ていない")
			}
			if errOut != "" {
				t.Errorf("stderr = %q", errOut)
			}
		})
	}
}

func writeDockerNoticeCache(t *testing.T, path string, stats docker.Stats) {
	t.Helper()
	b, err := json.Marshal(stats)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		t.Fatal(err)
	}
}
