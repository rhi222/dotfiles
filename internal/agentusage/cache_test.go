package agentusage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCacheRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sub", "usage.json") // 親ディレクトリも作られること
	c := Cache{Claude: &Side{FetchedAt: 100, Session: &Window{Percent: 45, ResetsAt: 200}}}
	if err := WriteCache(path, c); err != nil {
		t.Fatalf("WriteCache: %v", err)
	}
	got, err := LoadCache(path)
	if err != nil {
		t.Fatalf("LoadCache: %v", err)
	}
	if got.Claude == nil || got.Claude.Session == nil || got.Claude.Session.Percent != 45 {
		t.Errorf("round trip 失敗: %+v", got)
	}
}

func TestLoadCacheMissing(t *testing.T) {
	_, err := LoadCache(filepath.Join(t.TempDir(), "none.json"))
	if err == nil {
		t.Error("無いファイルで err が nil")
	}
}

func TestLoadCacheCorrupt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bad.json")
	os.WriteFile(path, []byte("{broken"), 0o644)
	if _, err := LoadCache(path); err == nil {
		t.Error("壊れた JSON で err が nil")
	}
}
