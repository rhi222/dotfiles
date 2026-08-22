package agentusage

import (
	"strings"
	"testing"
	"time"
)

func TestFormatCountdown(t *testing.T) {
	cases := []struct {
		d    time.Duration
		want string
	}{
		{-5 * time.Minute, "0m"},
		{0, "0m"},
		{30 * time.Second, "0m"},
		{59 * time.Minute, "59m"},
		{60 * time.Minute, "1h0m"},
		{2*time.Hour + 47*time.Minute, "2h47m"},
		{23*time.Hour + 59*time.Minute, "23h59m"},
		{24 * time.Hour, "1d0h"},
		{3*24*time.Hour + 11*time.Hour + 40*time.Minute, "3d11h"},
	}
	for _, c := range cases {
		if got := FormatCountdown(c.d); got != c.want {
			t.Errorf("FormatCountdown(%v) = %q, want %q", c.d, got, c.want)
		}
	}
}

// now を固定してレンダリングを検証する。epoch は now からの相対で組み立てる。
func fixtureCache(now time.Time) Cache {
	return Cache{
		Claude: &Side{
			FetchedAt: now.Add(-1 * time.Minute).Unix(),
			Session:   &Window{Percent: 45, ResetsAt: now.Add(2*time.Hour + 47*time.Minute).Unix()},
			Weekly:    &Window{Percent: 50, ResetsAt: now.Add(3*24*time.Hour + 11*time.Hour).Unix()},
			Fable:     &Window{Percent: 29, ResetsAt: now.Add(3*24*time.Hour + 11*time.Hour).Unix()},
		},
		Codex: &Side{
			FetchedAt: now.Add(-1 * time.Minute).Unix(),
			Weekly:    &Window{Percent: 2, ResetsAt: now.Add(4*24*time.Hour + 8*time.Hour).Unix()},
		},
	}
}

func TestRenderLineFresh(t *testing.T) {
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	got := RenderLine(fixtureCache(now), now, 15*time.Minute)
	want := "CC 45(2h47m) W50 F29(3d11h) · CX 2(4d8h)"
	if got != want {
		t.Errorf("RenderLine = %q, want %q", got, want)
	}
}

func TestRenderLineStale(t *testing.T) {
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	c := fixtureCache(now)
	c.Claude.FetchedAt = now.Add(-20 * time.Minute).Unix() // staleAfter=15m を超過
	got := RenderLine(c, now, 15*time.Minute)
	want := "CC 45?(2h47m) W50? F29?(3d11h) · CX 2(4d8h)"
	if got != want {
		t.Errorf("RenderLine = %q, want %q", got, want)
	}
}

func TestRenderLineResetPassed(t *testing.T) {
	// resets_at を過ぎた%は窓が切り替わった後の古い値なので ? を付ける
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	c := fixtureCache(now)
	c.Claude.Session.ResetsAt = now.Add(-1 * time.Minute).Unix()
	got := RenderLine(c, now, 15*time.Minute)
	want := "CC 45?(0m) W50? F29?(3d11h) · CX 2(4d8h)"
	if got != want {
		t.Errorf("RenderLine = %q, want %q", got, want)
	}
}

func TestRenderLinePartial(t *testing.T) {
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	c := fixtureCache(now)
	c.Claude = nil // Claude 側キャッシュがまだ無い → 欄ごと落とす
	got := RenderLine(c, now, 15*time.Minute)
	want := "CX 2(4d8h)"
	if got != want {
		t.Errorf("RenderLine = %q, want %q", got, want)
	}
}

func TestRenderLineFableMissing(t *testing.T) {
	// weekly_scoped がレスポンスに無いアカウントでは F を出さず、countdown は W に付く
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	c := fixtureCache(now)
	c.Claude.Fable = nil
	got := RenderLine(c, now, 15*time.Minute)
	want := "CC 45(2h47m) W50(3d11h) · CX 2(4d8h)"
	if got != want {
		t.Errorf("RenderLine = %q, want %q", got, want)
	}
}

func TestRenderLineEmpty(t *testing.T) {
	now := time.Now()
	if got := RenderLine(Cache{}, now, 15*time.Minute); got != "" {
		t.Errorf("RenderLine(empty) = %q, want empty", got)
	}
}

func TestRenderDetail(t *testing.T) {
	now := time.Date(2026, 8, 22, 10, 0, 0, 0, time.UTC)
	got := RenderDetail(fixtureCache(now), now, 15*time.Minute)
	for _, want := range []string{
		"Claude Code",
		"Session 5h", "45%",
		"Weekly", "50%",
		"Fable wk", "29%",
		"Codex", "2%",
		"▰▰▰▰▱▱▱▱", // 45% → 8マス中4マス（四捨五入）
		"fetched",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("RenderDetail に %q が無い:\n%s", want, got)
		}
	}
}

func TestRenderDetailEmpty(t *testing.T) {
	got := RenderDetail(Cache{}, time.Now(), 15*time.Minute)
	if !strings.Contains(got, "キャッシュ") {
		t.Errorf("空キャッシュの案内が無い: %q", got)
	}
}
