package agentusage

import (
	"fmt"
	"strings"
	"time"
)

// FormatCountdown は残り時間を幅が動きにくい2単位固定で出す。
// 1時間未満は "59m"、1日未満は "2h47m"、それ以上は "3d11h"。負値は "0m"。
func FormatCountdown(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	mins := int(d / time.Minute)
	switch {
	case mins < 60:
		return fmt.Sprintf("%dm", mins)
	case mins < 24*60:
		return fmt.Sprintf("%dh%dm", mins/60, mins%60)
	default:
		return fmt.Sprintf("%dd%dh", mins/(24*60), (mins%(24*60))/60)
	}
}

// sideStale は「?を付けるか」。fetched_at が staleAfter より古い、または
// 表示するどれかの窓の resets_at を過ぎている（窓が切り替わったのに%が古い）とき真。
func sideStale(s *Side, now time.Time, staleAfter time.Duration) bool {
	if now.Unix()-s.FetchedAt > int64(staleAfter/time.Second) {
		return true
	}
	for _, w := range []*Window{s.Session, s.Weekly, s.Fable} {
		if w != nil && w.ResetsAt > 0 && w.ResetsAt <= now.Unix() {
			return true
		}
	}
	return false
}

func countdown(w *Window, now time.Time) string {
	return FormatCountdown(time.Unix(w.ResetsAt, 0).Sub(now))
}

// RenderLine は tab bar 用の1行。herdr は成功した出力の最終行だけを使うので
// 必ず1行に閉じる（改行を含めない）。キャッシュが無い側は欄ごと落とす。
func RenderLine(c Cache, now time.Time, staleAfter time.Duration) string {
	var parts []string
	if s := c.Claude; s != nil && s.Session != nil && s.Weekly != nil {
		mark := ""
		if sideStale(s, now, staleAfter) {
			mark = "?"
		}
		p := fmt.Sprintf("CC %d%s(%s)", s.Session.Percent, mark, countdown(s.Session, now))
		if s.Fable != nil {
			p += fmt.Sprintf(" W%d%s F%d%s(%s)", s.Weekly.Percent, mark, s.Fable.Percent, mark, countdown(s.Weekly, now))
		} else {
			p += fmt.Sprintf(" W%d%s(%s)", s.Weekly.Percent, mark, countdown(s.Weekly, now))
		}
		parts = append(parts, p)
	}
	if s := c.Codex; s != nil && s.Weekly != nil {
		mark := ""
		if sideStale(s, now, staleAfter) {
			mark = "?"
		}
		parts = append(parts, fmt.Sprintf("CX %d%s(%s)", s.Weekly.Percent, mark, countdown(s.Weekly, now)))
	}
	return strings.Join(parts, " · ")
}

// bar は 8マスの使用率バー。popup は通常ペインなので Unicode を使ってよい。
func bar(percent int) string {
	filled := (percent*8 + 50) / 100
	if filled < 0 {
		filled = 0
	}
	if filled > 8 {
		filled = 8
	}
	return strings.Repeat("▰", filled) + strings.Repeat("▱", 8-filled)
}

func detailRow(label string, w *Window, now time.Time, withCountdown bool) string {
	r := time.Unix(w.ResetsAt, 0).Local()
	row := fmt.Sprintf("  %-11s %s %3d%%  reset %d/%d %02d:%02d",
		label, bar(w.Percent), w.Percent, int(r.Month()), r.Day(), r.Hour(), r.Minute())
	if withCountdown {
		row += fmt.Sprintf(" (%s)", countdown(w, now))
	}
	return row
}

func fetchedAgo(s *Side, now time.Time) string {
	return FormatCountdown(now.Sub(time.Unix(s.FetchedAt, 0)))
}

// RenderDetail は popup 用の詳細表示。
func RenderDetail(c Cache, now time.Time, staleAfter time.Duration) string {
	if c.Claude == nil && c.Codex == nil {
		return "キャッシュがまだ無い。dotctl agent-usage refresh を実行するか、しばらく待つ。"
	}
	var b strings.Builder
	var fetched []string
	if s := c.Claude; s != nil {
		b.WriteString("Claude Code\n")
		if s.Session != nil {
			b.WriteString(detailRow("Session 5h", s.Session, now, true) + "\n")
		}
		if s.Weekly != nil {
			b.WriteString(detailRow("Weekly", s.Weekly, now, true) + "\n")
		}
		if s.Fable != nil {
			b.WriteString(detailRow("Fable wk", s.Fable, now, false) + "\n")
		}
		note := ""
		if sideStale(s, now, staleAfter) {
			note = " [stale]"
		}
		fetched = append(fetched, fmt.Sprintf("claude %s前%s", fetchedAgo(s, now), note))
	}
	if s := c.Codex; s != nil && s.Weekly != nil {
		b.WriteString("Codex\n")
		b.WriteString(detailRow("Weekly", s.Weekly, now, true) + "\n")
		note := ""
		if sideStale(s, now, staleAfter) {
			note = " [stale]"
		}
		fetched = append(fetched, fmt.Sprintf("codex %s前%s", fetchedAgo(s, now), note))
	}
	b.WriteString("\nfetched: " + strings.Join(fetched, " / "))
	return b.String()
}
