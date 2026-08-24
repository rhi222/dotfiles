package agentusage

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"
)

// Config は agent-usage の参照先。パスの既定値と環境変数の対応は
// cmd/dotctl 側（agentUsageConfig）が持つ。
type Config struct {
	CacheFile        string
	CredentialsFile  string
	CodexBin         string
	CodexTimeout     time.Duration
	Endpoint         string
	TTL              time.Duration // これより古ければバックグラウンド再取得
	StaleAfter       time.Duration // これより古ければ ? 付き表示
	HTTPTimeout      time.Duration
	Now              func() time.Time // テストで固定する。nil なら time.Now
}

// NowOrDefault は設定された時刻源を返す。テストは Now を固定し、
// 本番は未設定のまま time.Now に落ちる。**呼び出し側は Now を直接
// 呼ばずにこれを使う** — Now は nil のことがあり、command 層からは
// 非公開メソッドが見えないため。
func (c Config) NowOrDefault() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// Refresh は両側を取得してキャッシュを更新する。
//
// **片側失敗はその側の旧値を温存する。** Claude の 401 で Codex の表示まで
// 消すのは害が大きい。両側とも失敗したときだけ err（キャッシュは書かない）。
func Refresh(ctx context.Context, cfg Config) ([]error, error) {
	old, _ := LoadCache(cfg.CacheFile) // 無くても空でよい
	merged := old
	now := cfg.NowOrDefault()

	var errs []error
	client := &http.Client{Timeout: cfg.HTTPTimeout}
	if cl, err := FetchClaude(ctx, cfg.CredentialsFile, cfg.Endpoint, client, now); err != nil {
		errs = append(errs, fmt.Errorf("claude: %w", err))
	} else {
		merged.Claude = cl
	}
	if cx, err := FetchCodex(ctx, cfg.CodexBin, cfg.CodexTimeout, now); err != nil {
		errs = append(errs, fmt.Errorf("codex: %w", err))
	} else {
		merged.Codex = cx
	}

	if len(errs) == 2 {
		return nil, errors.Join(errs...)
	}
	return nil, WriteCache(cfg.CacheFile, merged)
}
