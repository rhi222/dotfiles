package agentusage

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os/exec"
	"syscall"
	"time"
)

// weeklyWindowMinutes 以上の窓を「weekly」とみなす（10080分 = 7日）。
const weeklyWindowMinutes = 10080

// codexRateLimitsID は account/rateLimits/read に付ける JSON-RPC id。
// app-server は通知やサーバ→クライアント要求も同じ stdout に流すので、
// この id の応答だけを拾う。
const codexRateLimitsID = 2

// FetchCodex は codex app-server の account/rateLimits/read から 5h と weekly を取る。
//
// codex-cli 0.149 で `~/.codex/sessions/**/rollout-*.jsonl` は legacy になり
// （`codex migrate-rollouts` 参照）、ファイルからは rate_limits を拾えなくなった。
// 代わりに app-server を stdio JSON-RPC で1往復させる。
// **ここは codex 側の実装詳細に乗っている。** 壊れたときは err を返して
// 旧キャッシュ温存（stale 表示）に倒れる。
func FetchCodex(ctx context.Context, bin string, timeout time.Duration, now time.Time) (*Side, error) {
	return FetchCodexHome(ctx, bin, "", timeout, now)
}

// FetchCodexHome は指定した CODEX_HOME の認証で 5h と weekly の上限を取る。
// codexHome が空なら呼び出し元の環境をそのまま継承する。
func FetchCodexHome(ctx context.Context, bin, codexHome string, timeout time.Duration, now time.Time) (*Side, error) {
	if timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}
	result, err := codexRateLimits(ctx, bin, codexHome)
	if err != nil {
		return nil, err
	}
	session, weekly, err := windowsFromRateLimits(result)
	if err != nil {
		return nil, err
	}
	return &Side{FetchedAt: now.Unix(), Session: session, Weekly: weekly}, nil
}

// codexRateLimits は app-server を起動して account/rateLimits/read の result を返す。
//
// initialize → initialized → rateLimits を待たずに続けて書く。
// app-server は要求を順に処理するので往復を減らせる。
func codexRateLimits(ctx context.Context, bin, codexHome string) (json.RawMessage, error) {
	cmd := exec.CommandContext(ctx, bin, "app-server")
	if codexHome != "" {
		cmd.Env = append(cmd.Environ(), "CODEX_HOME="+codexHome)
	}
	// 自前のプロセスグループにして、抜けるときに孫まで確実に殺す。
	// app-server が子を残すと stdout の書き手が残り、読み出しが返らない
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	// stderr は捨てる。アカウント情報や token が載りうるので残さない
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("codex app-server の起動に失敗: %w", err)
	}
	defer func() {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		_ = cmd.Wait()
	}()

	// **応答を読み終えるまで stdin を閉じない。** app-server は stdin の EOF を
	// 終了要求として扱い、要求を処理し終える前に落ちる。
	// 書き込みエラーはここでは返さない。app-server が先に死んでいれば
	// 読み出し側で EOF になり、そちらの方が原因を説明できる
	defer stdin.Close()
	enc := json.NewEncoder(stdin)
	for _, msg := range codexHandshake() {
		if err := enc.Encode(msg); err != nil {
			break
		}
	}

	// 読み出しは goroutine に逃がす。**pipe の EOF に timeout を任せない** —
	// app-server が孫プロセスへ stdout を渡していると、親を殺しても
	// 書き手が残って Scan が返らない
	type readResult struct {
		raw json.RawMessage
		err error
	}
	done := make(chan readResult, 1)
	go func() {
		raw, err := readCodexResult(stdout)
		done <- readResult{raw, err}
	}()
	select {
	case <-ctx.Done():
		return nil, fmt.Errorf("codex app-server が応答しない: %w", ctx.Err())
	case r := <-done:
		return r.raw, r.err
	}
}

func codexHandshake() []any {
	return []any{
		map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{
			"clientInfo": map[string]any{"name": "dotctl", "title": "dotctl agent-usage", "version": "1"},
		}},
		map[string]any{"jsonrpc": "2.0", "method": "initialized", "params": map[string]any{}},
		map[string]any{"jsonrpc": "2.0", "id": codexRateLimitsID, "method": "account/rateLimits/read", "params": map[string]any{}},
	}
}

// readCodexResult は codexRateLimitsID の応答が来るまで stdout を読み飛ばす。
// パースできない行・別 id の行は無視する（app-server は通知も混ぜてくる）。
func readCodexResult(r io.Reader) (json.RawMessage, error) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		var m struct {
			ID     *int            `json:"id"`
			Result json.RawMessage `json:"result"`
			Error  *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if err := json.Unmarshal(sc.Bytes(), &m); err != nil {
			continue
		}
		if m.ID == nil || *m.ID != codexRateLimitsID {
			continue
		}
		if m.Error != nil {
			return nil, fmt.Errorf("account/rateLimits/read が error を返した: %s", m.Error.Message)
		}
		return m.Result, nil
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("app-server の応答の読み出しに失敗: %w", err)
	}
	return nil, fmt.Errorf("app-server が account/rateLimits/read に応答しなかった")
}

// windowsFromRateLimits は result から 5h 窓と weekly 窓を取り出す。
//
// **primary / secondary のどちらが 5h かは決め打ちしない。** 現状の実アカウントは
// primary=300分・secondary=10080分 だが、窓の長さで選べば並びが入れ替わっても壊れない。
// weekly は表示の必須要素なので取れなければ err、5h は取れなければ nil（欄ごと落とす）。
func windowsFromRateLimits(result json.RawMessage) (session, weekly *Window, err error) {
	var body struct {
		RateLimits *struct {
			Primary   *codexWindow `json:"primary"`
			Secondary *codexWindow `json:"secondary"`
		} `json:"rateLimits"`
	}
	if err := json.Unmarshal(result, &body); err != nil {
		return nil, nil, fmt.Errorf("rateLimits のパースに失敗: %w", err)
	}
	if body.RateLimits == nil {
		return nil, nil, fmt.Errorf("応答に rateLimits が無い")
	}
	windows := []*codexWindow{body.RateLimits.Primary, body.RateLimits.Secondary}
	weeklyRaw := pickWeekly(windows)
	if weeklyRaw == nil {
		return nil, nil, fmt.Errorf("rateLimits に窓が1つも無い")
	}
	return toWindow(pickSession(windows, weeklyRaw)), toWindow(weeklyRaw), nil
}

type codexWindow struct {
	UsedPercent   float64 `json:"usedPercent"`
	WindowMinutes int     `json:"windowDurationMins"`
	ResetsAt      int64   `json:"resetsAt"`
}

func toWindow(w *codexWindow) *Window {
	if w == nil {
		return nil
	}
	return &Window{Percent: int(math.Round(w.UsedPercent)), ResetsAt: w.ResetsAt}
}

// pickWeekly は weekly 窓（>= 10080 分）を選ぶ。
// 窓の長さが分からない応答では最初の窓を weekly とみなす。
func pickWeekly(windows []*codexWindow) *codexWindow {
	for _, w := range windows {
		if w != nil && w.WindowMinutes >= weeklyWindowMinutes {
			return w
		}
	}
	for _, w := range windows {
		if w != nil {
			return w
		}
	}
	return nil
}

// pickSession は weekly より短い窓（実際は 300 分）を選ぶ。
// weekly に採った窓は除く。長さ不明（0分）の窓は 5h と断定できないので選ばない。
func pickSession(windows []*codexWindow, weekly *codexWindow) *codexWindow {
	for _, w := range windows {
		if w != nil && w != weekly && w.WindowMinutes > 0 && w.WindowMinutes < weeklyWindowMinutes {
			return w
		}
	}
	return nil
}
