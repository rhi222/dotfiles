package docker

import "strings"

// DisplayWidth は端末での表示幅を返す（East Asian Wide / Fullwidth を2として数える）。
//
// **fish の `string pad` はこの幅で詰める。** Go の `fmt` の %-18s はルーン数、
// bash の printf はバイト数で詰めるので、どちらを使っても日本語ラベルの桁が
// 崩れる。プレビューは日本語ラベルを並べる表なので、ここを合わせないと
// 見た目が壊れる。
func DisplayWidth(s string) int {
	w := 0
	for _, r := range s {
		w += runeWidth(r)
	}
	return w
}

// runeWidth は1文字の表示幅。
//
// 対象は設定ファイルとプレビューに出る範囲に絞っている（CJK・かな・全角記号）。
// **完全な wcwidth は実装しない。** 出てこない範囲まで抱えると、合っている
// ことを確かめられないコードが増える。
func runeWidth(r rune) int {
	switch {
	case r < 0x1100:
		return 1
	case r >= 0x1100 && r <= 0x115F, // Hangul Jamo
		r == 0x2329, r == 0x232A,
		r >= 0x2E80 && r <= 0x303E,   // CJK Radicals, Kangxi, CJK 記号（々 〜 など）
		r >= 0x3041 && r <= 0x33FF,   // ひらがな・カタカナ・CJK 互換
		r >= 0x3400 && r <= 0x4DBF,   // CJK 拡張A
		r >= 0x4E00 && r <= 0x9FFF,   // CJK 統合漢字
		r >= 0xA000 && r <= 0xA4CF,   // Yi
		r >= 0xAC00 && r <= 0xD7A3,   // ハングル音節
		r >= 0xF900 && r <= 0xFAFF,   // CJK 互換漢字
		r >= 0xFE10 && r <= 0xFE19,   // 縦書き形
		r >= 0xFE30 && r <= 0xFE6F,   // CJK 互換形・小字形
		r >= 0xFF00 && r <= 0xFF60,   // 全角英数・記号
		r >= 0xFFE0 && r <= 0xFFE6,   // 全角通貨記号
		r >= 0x1F300 && r <= 0x1F64F, // 絵文字（🗑 など）
		r >= 0x1F900 && r <= 0x1F9FF,
		r >= 0x20000 && r <= 0x3FFFD: // CJK 拡張B以降
		return 2
	default:
		return 1
	}
}

// PadRight は表示幅が n になるまで右へスペースを詰める（fish の `string pad -r -w n`）。
func PadRight(s string, n int) string {
	if d := n - DisplayWidth(s); d > 0 {
		return s + strings.Repeat(" ", d)
	}
	return s
}

// PadLeft は表示幅が n になるまで左へスペースを詰める（fish の `string pad -w n`）。
func PadLeft(s string, n int) string {
	if d := n - DisplayWidth(s); d > 0 {
		return strings.Repeat(" ", d) + s
	}
	return s
}
