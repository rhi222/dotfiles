package worktree

import (
	"strings"
	"testing"
)

// **bash の printf %-44s はバイト数で詰める。Go の fmt %-44s はルーン数で詰める。**
// `（detached）` は 1文字3バイトの全角を含むので、素朴に移植すると Shell 版と
// 桁がずれる。出力を代表 fixture で比較する以上、ここは意図して合わせる。
func TestPadRightUsesByteWidthLikeBash(t *testing.T) {
	tests := []struct {
		in   string
		want int // 期待する結果のバイト長
	}{
		{"feat-a", 44},
		{"", 44},
		{"（detached）", 44},            // 全角括弧 3バイト×2 + detached 8 = 14バイト
		{strings.Repeat("x", 44), 44}, // ちょうど
		{strings.Repeat("x", 50), 50}, // 超過分は切らない
		{strings.Repeat("あ", 20), 60}, // 60バイトなので詰めない
	}
	for _, tt := range tests {
		got := padRight(tt.in, 44)
		if len(got) != tt.want {
			t.Errorf("padRight(%q) のバイト長 = %d, want %d", tt.in, len(got), tt.want)
		}
		if !strings.HasPrefix(got, tt.in) {
			t.Errorf("padRight(%q) = %q: 元の文字列が先頭に無い", tt.in, got)
		}
	}
}

func TestPadRightMatchesBashForFullWidthLabel(t *testing.T) {
	// bash: printf '%-44s' '（detached）' は 14バイト + 30スペース
	got := padRight("（detached）", 44)
	if want := "（detached）" + strings.Repeat(" ", 30); got != want {
		t.Errorf("got  %q\nwant %q", got, want)
	}
}

// KB の整形は du -sh の単位表記に寄せる。
func TestFormatKB(t *testing.T) {
	tests := []struct {
		kb   int
		want string
	}{
		{0, "0K"},
		{1, "1K"},
		{1023, "1023K"},
		{1024, "1M"},
		{1536, "1M"}, // 整数切り捨て（bash の %d と同じ）
		{2048, "2M"},
		{1048575, "1023M"},
		{1048576, "1.0G"},
		{1572864, "1.5G"},
	}
	for _, tt := range tests {
		if got := formatKB(tt.kb); got != tt.want {
			t.Errorf("formatKB(%d) = %q, want %q", tt.kb, got, tt.want)
		}
	}
}

// 表示は Plan だけを読む。**dry-run と実削除で同じ Plan を参照する**ので、
// 「表示したものと消すものが違う」状態が構造的に起きない。
func TestRenderDryRun(t *testing.T) {
	p := &Plan{
		Roots: "/data/git-repos",
		Repos: []RepoPlan{{
			Repo: "/data/git-repos/example.com/o/r",
			Items: []Item{
				{Path: "/w/a", Branch: "feat-a", Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
				{Path: "/w/b", Branch: "", Decision: Decision{Verdict: SKIP, Reason: "detached HEAD（PR判定不能）", SkipKind: SkipDetached}},
				{Path: "/w/c", Branch: "feat-c", Decision: Decision{Verdict: PRUNE, Reason: "ディレクトリ消失 (x)"}},
				{Path: "/w/d", Branch: "feat-d", Decision: Decision{Verdict: KEEP, Reason: "PR なし"}},
			},
		}},
	}
	out := renderAll(p, RenderOptions{})

	for _, want := range []string{
		"worktree cleanup  mode: DRY-RUN（試走／削除しません）",
		"走査ルート: /data/git-repos",
		"== /data/git-repos/example.com/o/r ==",
		"  [DELETE] ",
		"  [SKIP  ] ",
		"  [PRUNE ] ",
		"  [KEEP  ] ",
		"== サマリ ==",
		"  DELETE 候補: 1 件",
		"  PRUNE  対象: 1 件",
		"  SKIP       : 1 件 (locked 0 / detached 1 / 未コミット変更 0)",
		"  KEEP       : 1 件",
		"worktree-cleanup: DELETE_CANDIDATES=1 PRUNE=1 SKIP=1 KEEP=1",
		"これは dry-run です。",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("出力に %q が無い:\n%s", want, out)
		}
	}
	// detached のラベルは括弧つき
	if !strings.Contains(out, "（detached）") {
		t.Error("detached のラベルが出ていない")
	}
	// dry-run では実削除の内訳を出さない
	if strings.Contains(out, "DELETED=") {
		t.Error("dry-run で DELETED= を出してはいけない")
	}
}

func TestRenderExecuteChangesSummaryWording(t *testing.T) {
	// **dry-run と --execute で意味が違うので文言を分ける。** --execute のまま
	// 「候補」と出すと「消したのにまだ候補が残っている」と読める
	p := &Plan{
		Roots: "/r",
		Repos: []RepoPlan{{Repo: "/r/x", Items: []Item{
			{Path: "/w/a", Branch: "a", Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
		}}},
		Executed:     true,
		Deleted:      1,
		DeleteFailed: 0,
	}
	out := renderAll(p, RenderOptions{Execute: true})

	if !strings.Contains(out, "  削除       : 1 件") {
		t.Errorf("実削除の件数が出ていない:\n%s", out)
	}
	if strings.Contains(out, "DELETE 候補") {
		t.Error("--execute では「候補」と出さない")
	}
	// **失敗0件のときに行を出すと、失敗が常態のように見えるので出さない**
	if strings.Contains(out, "削除失敗") {
		t.Error("失敗0件なら削除失敗行を出さない")
	}
	// 機械可読行は常に分類結果を持ち、--execute のときだけ内訳を足す
	if !strings.Contains(out, "worktree-cleanup: DELETE_CANDIDATES=1 PRUNE=0 SKIP=0 KEEP=0 DELETED=1 DELETE_FAILED=0") {
		t.Errorf("機械可読行が違う:\n%s", out)
	}
	if strings.Contains(out, "これは dry-run です") {
		t.Error("--execute で dry-run の案内を出してはいけない")
	}
}

func TestRenderShowsDeleteFailuresWhenPresent(t *testing.T) {
	p := &Plan{Roots: "/r", Executed: true, Deleted: 1, DeleteFailed: 2}
	out := renderAll(p, RenderOptions{Execute: true})
	if !strings.Contains(out, "削除失敗   : 2 件") {
		t.Errorf("失敗件数が出ていない:\n%s", out)
	}
}

func TestRenderSizeColumn(t *testing.T) {
	p := &Plan{
		Roots: "/r",
		Repos: []RepoPlan{{Repo: "/r/x", Items: []Item{
			{Path: "/w/a", Branch: "a", SizeKB: 2048, Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
		}}},
		FreedKB: 2048,
	}
	out := renderAll(p, RenderOptions{ShowSize: true})
	if !strings.Contains(out, "MERGED #1  2M") {
		t.Errorf("DELETE 行にサイズが出ていない:\n%s", out)
	}
	if !strings.Contains(out, "  解放見込み : 2M") {
		t.Errorf("解放見込みが出ていない:\n%s", out)
	}
}

func TestRenderSkipsReposWithoutLinkedWorktrees(t *testing.T) {
	// linked worktree が無いリポジトリはセクションごと出さない（出力を静かに保つ）
	p := &Plan{Roots: "/r", Repos: []RepoPlan{{Repo: "/r/quiet", Items: nil}}}
	out := renderAll(p, RenderOptions{})
	if strings.Contains(out, "/r/quiet") {
		t.Errorf("空のリポジトリのセクションを出している:\n%s", out)
	}
}

func TestRenderNoColorWhenNotTTY(t *testing.T) {
	p := &Plan{Roots: "/r", Repos: []RepoPlan{{Repo: "/r/x", Items: []Item{
		{Path: "/w/a", Branch: "a", Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
	}}}}
	out := renderAll(p, RenderOptions{})
	if strings.Contains(out, "\x1b[") {
		t.Errorf("TTY でないときに ANSI を出してはいけない:\n%q", out)
	}
}

func TestRenderColorWhenTTY(t *testing.T) {
	p := &Plan{Roots: "/r", Repos: []RepoPlan{{Repo: "/r/x", Items: []Item{
		{Path: "/w/a", Branch: "a", Decision: Decision{Verdict: DELETE, Reason: "MERGED #1"}},
	}}}}
	out := renderAll(p, RenderOptions{Color: true})
	if !strings.Contains(out, "\x1b[32m") {
		t.Errorf("TTY のときは DELETE を緑にする:\n%q", out)
	}
}

// renderAll は本文とサマリを続けて返す（Shell 版1回分の出力に相当）。
func renderAll(p *Plan, opt RenderOptions) string {
	return RenderHead(p, opt) + RenderSummary(p, opt)
}
