package agentusage

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// FetchClaude は Claude Code の OAuth usage エンドポイントからレート上限を取る。
//
// **非公式エンドポイント。** Claude Code 本体の /usage が使うものと同じで、
// 仕様変更で壊れうる。401 と 5xx は credentials を読み直して1回だけ再試行する。
// それでも壊れたときは err を返して旧キャッシュ温存（? 表示）に倒れる設計なので、
// ここでは防御的パースより「読めなければ全体を err」を選ぶ。
// token とレスポンス本文はログにも err メッセージにも入れない。
func FetchClaude(ctx context.Context, credentialsFile, endpoint string, client *http.Client, now time.Time) (*Side, error) {
	const maxAttempts = 2
	for attempt := range maxAttempts {
		token, err := readAccessToken(credentialsFile)
		if err != nil {
			return nil, err
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("anthropic-beta", "oauth-2025-04-20")

		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		if resp.StatusCode != http.StatusOK {
			// 本文は token の失効理由などを含みうるので読み捨てる
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			if attempt+1 < maxAttempts && retryClaudeUsage(resp.StatusCode) {
				continue
			}
			if resp.StatusCode == http.StatusUnauthorized {
				return nil, fmt.Errorf("usage API が現在の access token を拒否した。Claude Code 本体はログイン済みでも、usage 用の短命 token だけが古い場合がある。新しい `claude` プロセスを起動して token 更新後、`dotctl agent-usage refresh` を再実行する。続く場合は `claude auth login` で再ログインする（usage エンドポイント: 401、1回再試行済み）")
			}
			if attempt > 0 {
				return nil, fmt.Errorf("usage エンドポイントが %d を返した（1回再試行済み）", resp.StatusCode)
			}
			return nil, fmt.Errorf("usage エンドポイントが %d を返した", resp.StatusCode)
		}

		var body struct {
			Limits []struct {
				Kind     string `json:"kind"`
				Percent  int    `json:"percent"`
				ResetsAt string `json:"resets_at"`
			} `json:"limits"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
			resp.Body.Close()
			return nil, fmt.Errorf("usage レスポンスのパースに失敗: %w", err)
		}
		resp.Body.Close()

		s := &Side{FetchedAt: now.Unix()}
		for _, l := range body.Limits {
			w := &Window{Percent: l.Percent, ResetsAt: parseResetsAt(l.ResetsAt)}
			switch l.Kind {
			case "session":
				s.Session = w
			case "weekly_all":
				s.Weekly = w
			case "weekly_scoped":
				// scope はモデル別 weekly（今は Fable のみ観測）。複数来たら最初を採る
				if s.Fable == nil {
					s.Fable = w
				}
			}
		}
		if s.Session == nil || s.Weekly == nil {
			return nil, fmt.Errorf("usage レスポンスに session/weekly_all が無い（仕様変更の可能性）")
		}
		return s, nil
	}
	panic("unreachable")
}

func retryClaudeUsage(status int) bool {
	return status == http.StatusUnauthorized || status >= http.StatusInternalServerError
}

func readAccessToken(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	var creds struct {
		ClaudeAiOauth struct {
			AccessToken string `json:"accessToken"`
		} `json:"claudeAiOauth"`
	}
	if err := json.Unmarshal(b, &creds); err != nil {
		return "", fmt.Errorf("credentials のパースに失敗: %w", err)
	}
	if creds.ClaudeAiOauth.AccessToken == "" {
		return "", fmt.Errorf("credentials に accessToken が無い")
	}
	return creds.ClaudeAiOauth.AccessToken, nil
}

// parseResetsAt は RFC3339（小数秒あり得る）を epoch 秒へ。読めなければ 0。
func parseResetsAt(s string) int64 {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return 0
	}
	return t.Unix()
}
