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
		p := fmt.Sprintf("CC s%d%%", s.Session.Percent)
		if s.Fable != nil {
			p += fmt.Sprintf(" w%d%% f%d%%", s.Weekly.Percent, s.Fable.Percent)
		} else {
			p += fmt.Sprintf(" w%d%%", s.Weekly.Percent)
		}
		if sideStale(s, now, staleAfter) {
			p += " [stale]"
		}
		parts = append(parts, p)
	}
	if s := c.Codex; s != nil && s.Weekly != nil {
		p := fmt.Sprintf("CX w%d%%", s.Weekly.Percent)
		if sideStale(s, now, staleAfter) {
			p += " [stale]"
		}
		parts = append(parts, p)
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

const (
	ansiReset      = "\x1b[0m"
	ansiBold       = "\x1b[1m"
	ansiDim        = "\x1b[2m"
	ansiBoldRed    = "\x1b[1;31m"
	ansiBoldGreen  = "\x1b[1;32m"
	ansiBoldYellow = "\x1b[1;33m"
	ansiBoldCyan   = "\x1b[1;36m"
)

func styled(enabled bool, sgr, value string) string {
	if !enabled || value == "" {
		return value
	}
	return sgr + value + ansiReset
}

func usageColor(percent int) string {
	switch {
	case percent >= 85:
		return ansiBoldRed
	case percent >= 60:
		return ansiBoldYellow
	default:
		return ansiBoldGreen
	}
}

func detailBar(percent int, color bool) string {
	plain := bar(percent)
	if !color {
		return plain
	}
	filled := strings.TrimRight(plain, "▱")
	empty := strings.TrimLeft(plain, "▰")
	return styled(true, usageColor(percent), filled) + styled(true, ansiDim, empty)
}

func detailRow(label string, w *Window, now time.Time, withCountdown, color bool) string {
	r := time.Unix(w.ResetsAt, 0).Local()
	reset := fmt.Sprintf("reset %d/%d %02d:%02d", int(r.Month()), r.Day(), r.Hour(), r.Minute())
	if withCountdown {
		reset += fmt.Sprintf(" (%s)", countdown(w, now))
	}
	return fmt.Sprintf("  %s %s %s  %s",
		styled(color, ansiBold, fmt.Sprintf("%-11s", label)),
		detailBar(w.Percent, color),
		styled(color, usageColor(w.Percent), fmt.Sprintf("%3d%%", w.Percent)),
		styled(color, ansiDim, reset))
}

func fetchedAgo(s *Side, now time.Time) string {
	return FormatCountdown(now.Sub(time.Unix(s.FetchedAt, 0)))
}

// RenderDetail は popup 用の詳細表示（ANSI 色なし）。
func RenderDetail(c Cache, now time.Time, staleAfter time.Duration) string {
	return renderDetail(c, now, staleAfter, false)
}

// RenderDetailColor は通常の端末として動く popup 用の ANSI 色付き詳細表示。
func RenderDetailColor(c Cache, now time.Time, staleAfter time.Duration) string {
	return renderDetail(c, now, staleAfter, true)
}

func renderDetail(c Cache, now time.Time, staleAfter time.Duration, color bool) string {
	if c.Claude == nil && c.Codex == nil {
		return styled(color, ansiBoldYellow,
			"キャッシュがまだ無い。dotctl agent-usage refresh を実行するか、しばらく待つ。")
	}
	var b strings.Builder
	var fetched []string
	if s := c.Claude; s != nil {
		b.WriteString(styled(color, ansiBoldCyan, "Claude Code") + "\n")
		if s.Session != nil {
			b.WriteString(detailRow("Session 5h", s.Session, now, true, color) + "\n")
		}
		if s.Weekly != nil {
			b.WriteString(detailRow("Weekly", s.Weekly, now, true, color) + "\n")
		}
		if s.Fable != nil {
			b.WriteString(detailRow("Fable wk", s.Fable, now, false, color) + "\n")
		}
		fetchedText := styled(color, ansiDim, fmt.Sprintf("claude %s前", fetchedAgo(s, now)))
		if sideStale(s, now, staleAfter) {
			fetchedText += " " + styled(color, ansiBoldRed, "[stale]")
		}
		fetched = append(fetched, fetchedText)
	}
	if s := c.Codex; s != nil && s.Weekly != nil {
		b.WriteString(styled(color, ansiBoldCyan, "Codex") + "\n")
		b.WriteString(detailRow("Weekly", s.Weekly, now, true, color) + "\n")
		fetchedText := styled(color, ansiDim, fmt.Sprintf("codex %s前", fetchedAgo(s, now)))
		if sideStale(s, now, staleAfter) {
			fetchedText += " " + styled(color, ansiBoldRed, "[stale]")
		}
		fetched = append(fetched, fetchedText)
	}
	b.WriteString("\n" + styled(color, ansiDim, "fetched: ") +
		strings.Join(fetched, styled(color, ansiDim, " / ")))
	return b.String()
}
