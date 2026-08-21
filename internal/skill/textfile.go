// Package skill は Claude/Codex skill の監査と vendoring を行う。
package skill

import (
	"bytes"
	"os"
)

// IsTextFile はファイルがテキストなら true。
//
// **判定を `grep -Iq .` に合わせている。** skill-audit と skill-vendor で判定が
// ずれると、audit は HIGH で報告するのに vendor は取り込む（またはその逆）に
// なるため、ここ1か所に集約する。
//
// `file --mime` は使えない。コードブロックの多い .md を application/javascript と
// 判定するので、正当な rules/*.md が誤って弾かれる（実測で27件）。
//
// 実測した `grep -Iq .` の境界（GNU grep 3.11）:
//   - 空ファイル       -> テキストでない（マッチする行が無い）
//   - NUL を含む       -> テキストでない（位置は問わない。200KB 先でも検出する）
//   - 不正な UTF-8     -> **テキスト扱い**（NUL が無ければ通る）
func IsTextFile(path string) bool {
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	if len(b) == 0 {
		return false
	}
	return !bytes.ContainsRune(b, 0)
}

// IsBinaryFile はレビューできない非テキストファイルなら true。
//
// **空ファイルは非テキスト扱いにしない。** 中身が無いので害が無く、
// 弾くと空の .gitkeep のようなものまで取り込めなくなる。
func IsBinaryFile(path string) bool {
	st, err := os.Stat(path)
	if err != nil || st.Size() == 0 {
		return false
	}
	return !IsTextFile(path)
}
