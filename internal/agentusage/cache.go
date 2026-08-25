// Package agentusage は AI agent（Claude Code / Codex）のレート上限の
// 取得・キャッシュ・表示を担う。herdr の tab bar と popup から使われる。
//
// キャッシュに置くのは%と resets_at と fetched_at だけ。token や API の
// 生レスポンスはファイルにもログにも残さない（public repo 運用の境界）。
package agentusage

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Window は1つのレート窓。ResetsAt は epoch 秒（0 = 不明）。
type Window struct {
	Percent  int   `json:"percent"`
	ResetsAt int64 `json:"resets_at"`
}

// Side は agent 1つ分の取得結果。Codex は Weekly だけ使う。
type Side struct {
	FetchedAt int64   `json:"fetched_at"`
	Session   *Window `json:"session,omitempty"`
	Weekly    *Window `json:"weekly,omitempty"`
	Fable     *Window `json:"fable,omitempty"`
}

// Cache はキャッシュファイル全体。データ源ごとの更新と旧値温存を許すため個別に持つ。
type Cache struct {
	Claude        *Side `json:"claude,omitempty"`
	Codex         *Side `json:"codex,omitempty"`
	CodexOverride *Side `json:"codex_override,omitempty"`
}

// LoadCache はキャッシュを読む。無い・壊れているは err で返し、
// 呼び出し側が「欄ごと落とす」判断をする。
func LoadCache(path string) (Cache, error) {
	var c Cache
	b, err := os.ReadFile(path)
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return Cache{}, fmt.Errorf("キャッシュのパースに失敗: %w", err)
	}
	return c, nil
}

// WriteCache は同一ディレクトリの一時ファイル経由で原子的に書く。
// 壊れた JSON を読み手（1秒間隔で走る tab bar）へ見せないため。
func WriteCache(path string, c Cache) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	b, err := json.Marshal(c)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".usage-*.json")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	return os.Rename(name, path)
}
