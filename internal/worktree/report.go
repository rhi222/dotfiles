package worktree

import (
	"fmt"
	"strings"
)

// RenderOptions は表示の指定。
type RenderOptions struct {
	Execute  bool
	ShowSize bool
	Color    bool // stdout が TTY のときだけ真にする
}

const labelWidth = 44

// padRight は s を n バイトになるまで右側にスペースを詰める。
//
// **bash の printf %-44s はバイト数で詰めるが、Go の fmt %-44s はルーン数で
// 詰める。** `（detached）` は全角括弧を含むので、素朴に %-44s を使うと
// Shell 版と桁がずれる。移植では文言も桁も変えない方針なので、bash 側に合わせる。
func padRight(s string, n int) string {
	if len(s) >= n {
		return s
	}
	return s + strings.Repeat(" ", n-len(s))
}

// formatKB は KB を人間可読に整形する（du -sh の単位表記に寄せる）。
func formatKB(kb int) string {
	switch {
	case kb >= 1048576:
		return fmt.Sprintf("%.1fG", float64(kb)/1048576)
	case kb >= 1024:
		return fmt.Sprintf("%dM", kb/1024)
	default:
		return fmt.Sprintf("%dK", kb)
	}
}

type palette struct {
	bold, green, yellow, cyan, reset string
}

func newPalette(color bool) palette {
	if !color {
		return palette{}
	}
	return palette{
		bold:   "\x1b[1m",
		green:  "\x1b[32m",
		yellow: "\x1b[33m",
		cyan:   "\x1b[36m",
		reset:  "\x1b[0m",
	}
}

// Render は Plan を表示用の文字列にする。**Plan 以外は読まない**ので、
// dry-run と実削除で表示が食い違うことがない。
func Render(p *Plan, opt RenderOptions) string {
	c := newPalette(opt.Color)
	var b strings.Builder

	section := func(title string) {
		fmt.Fprintf(&b, "\n%s%s== %s ==%s\n", c.bold, c.cyan, title, c.reset)
	}

	mode := c.yellow + "DRY-RUN（試走／削除しません）" + c.reset
	if opt.Execute {
		mode = c.green + "EXECUTE（実削除）" + c.reset
	}
	fmt.Fprintf(&b, "%sworktree cleanup%s  mode: %s\n", c.bold, c.reset, mode)
	fmt.Fprintf(&b, "走査ルート: %s\n", p.Roots)

	for _, rp := range p.Repos {
		// linked worktree が無いリポジトリはセクションごと出さない（出力を静かに保つ）
		if len(rp.Items) == 0 {
			continue
		}
		section(rp.Repo)
		for _, it := range rp.Items {
			label := padRight(it.Label(), labelWidth)
			switch it.Decision.Verdict {
			case DELETE:
				note := ""
				if opt.ShowSize {
					note = "  " + formatKB(it.SizeKB)
				}
				fmt.Fprintf(&b, "  %s[DELETE]%s %s %s%s\n", c.green, c.reset, label, it.Decision.Reason, note)
			case PRUNE:
				fmt.Fprintf(&b, "  %s[PRUNE ]%s %s %s\n", c.cyan, c.reset, label, it.Decision.Reason)
			case SKIP:
				fmt.Fprintf(&b, "  %s[SKIP  ]%s %s %s\n", c.yellow, c.reset, label, it.Decision.Reason)
			default:
				fmt.Fprintf(&b, "  [KEEP  ] %s %s\n", label, it.Decision.Reason)
			}
		}
	}

	cnt := p.Counts()
	section("サマリ")
	// **dry-run と --execute で意味が違うので文言を分ける。** --execute のまま
	// 「候補」と出すと「消したのにまだ候補が残っている」と読めるうえ、削除に
	// 失敗した分まで成功に見える。
	if opt.Execute {
		fmt.Fprintf(&b, "  削除       : %d 件\n", p.Deleted)
		// 失敗0件のときに行を出すと、失敗が常態のように見えるので出さない。
		if p.DeleteFailed > 0 {
			fmt.Fprintf(&b, "  %s削除失敗   : %d 件%s\n", c.yellow, p.DeleteFailed, c.reset)
		}
	} else {
		fmt.Fprintf(&b, "  DELETE 候補: %d 件\n", cnt.Delete)
	}
	fmt.Fprintf(&b, "  PRUNE  対象: %d 件\n", cnt.Prune)
	fmt.Fprintf(&b, "  SKIP       : %d 件 (locked %d / detached %d / 未コミット変更 %d)\n",
		cnt.Skip, cnt.SkipLocked, cnt.SkipDetached, cnt.SkipDirty)
	fmt.Fprintf(&b, "  KEEP       : %d 件\n", cnt.Keep)
	if opt.ShowSize {
		fmt.Fprintf(&b, "  解放見込み : %s\n", formatKB(p.FreedKB))
	}

	// 機械可読サマリ行。daily-update.sh はこの行から件数を取る（表示行は grep しない）。
	// DELETE_CANDIDATES は常に分類結果の件数で、--execute のときだけ実削除の
	// 内訳を後ろに足す（daily-update.sh は dry-run でしか読まないので意味を変えない）。
	fmt.Fprintf(&b, "worktree-cleanup: DELETE_CANDIDATES=%d PRUNE=%d SKIP=%d KEEP=%d",
		cnt.Delete, cnt.Prune, cnt.Skip, cnt.Keep)
	if opt.Execute {
		fmt.Fprintf(&b, " DELETED=%d DELETE_FAILED=%d", p.Deleted, p.DeleteFailed)
	}
	b.WriteString("\n")

	if !opt.Execute {
		fmt.Fprintf(&b, "\n%sこれは dry-run です。実際に削除するには --execute を付けて再実行してください。%s\n",
			c.yellow, c.reset)
	}
	return b.String()
}
