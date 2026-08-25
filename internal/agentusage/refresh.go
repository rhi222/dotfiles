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
	CacheFile         string
	CredentialsFile   string
	CodexBin          string
	CodexOverrideHome string
	CodexTimeout      time.Duration
	Endpoint          string
	TTL               time.Duration // これより古ければバックグラウンド再取得
	StaleAfter        time.Duration // これより古ければ ? 付き表示
	HTTPTimeout       time.Duration
	Now               func() time.Time // テストで固定する。nil なら time.Now
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

// Refresh は設定された全データ源を並列取得してキャッシュを更新する。
//
// **一部失敗はそのデータ源の旧値を温存する。** Claude の 401 で Codex の表示まで
// 消すのは害が大きい。全データ源が失敗したときだけ err（キャッシュは書かない）。
//
// 一部失敗は warnings で返す。**握りつぶさない** — データ源が消えたときに
// 「欄が黙って消える」だけだと、原因に辿り着く手がかりが残らない。
func Refresh(ctx context.Context, cfg Config) ([]error, error) {
	old, _ := LoadCache(cfg.CacheFile) // 無くても空でよい
	merged := old
	if cfg.CodexOverrideHome == "" {
		merged.CodexOverride = nil
	}
	now := cfg.NowOrDefault()

	type fetchResult struct {
		kind string
		name string
		side *Side
		err  error
	}
	const (
		kindClaude        = "claude"
		kindCodex         = "codex"
		kindCodexOverride = "codex_override"
	)
	resultCount := 2
	if cfg.CodexOverrideHome != "" {
		resultCount++
	}
	results := make(chan fetchResult, resultCount)
	client := &http.Client{Timeout: cfg.HTTPTimeout}
	go func() {
		side, err := FetchClaude(ctx, cfg.CredentialsFile, cfg.Endpoint, client, now)
		results <- fetchResult{kind: kindClaude, name: "claude", side: side, err: err}
	}()
	defaultName := "codex"
	if cfg.CodexOverrideHome != "" {
		defaultName = "codex default"
	}
	go func() {
		side, err := FetchCodex(ctx, cfg.CodexBin, cfg.CodexTimeout, now)
		results <- fetchResult{kind: kindCodex, name: defaultName, side: side, err: err}
	}()
	if cfg.CodexOverrideHome != "" {
		go func() {
			side, err := FetchCodexHome(ctx, cfg.CodexBin, cfg.CodexOverrideHome, cfg.CodexTimeout, now)
			results <- fetchResult{kind: kindCodexOverride, name: "codex override", side: side, err: err}
		}()
	}

	byKind := make(map[string]fetchResult, resultCount)
	for range resultCount {
		result := <-results
		byKind[result.kind] = result
	}
	order := []string{kindClaude, kindCodex}
	if cfg.CodexOverrideHome != "" {
		order = append(order, kindCodexOverride)
	}
	var errs []error
	for _, kind := range order {
		result := byKind[kind]
		if result.err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", result.name, result.err))
			continue
		}
		switch result.kind {
		case kindClaude:
			merged.Claude = result.side
		case kindCodex:
			merged.Codex = result.side
		case kindCodexOverride:
			merged.CodexOverride = result.side
		}
	}

	if len(errs) == resultCount {
		return nil, errors.Join(errs...)
	}
	return errs, WriteCache(cfg.CacheFile, merged)
}
