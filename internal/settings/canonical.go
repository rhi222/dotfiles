// Package settings は設定ファイルのコピー同期（pull / push / status）を行う。
//
// **実ファイルを正とし、リポジトリがそれを追いかける**のが共通の思想。
// symlink にできない理由は対象ごとに違う（Claude Code は一時ファイル + rename で
// 書き戻す / Windows 側の実体は NTFS 上にあり WSL の symlink を解釈しない）が、
// 「リンクで戦っても必ず外れる」という結論は同じ。
package settings

import (
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

// Canonical は JSON を `jq -S .` と同じ形に正規化する。
//
// **差分を意味のある変更だけにするための正規化。** キー順が実行ごとに変わると
// 同期のたびに差分が出て、本当の変更が埋もれる。
//
// jq に合わせている点:
//   - キーは辞書順、インデントは2スペース、末尾に改行1つ
//   - HTML エスケープをしない（encoding/json の既定は < > & をエスケープする）
//   - 数値は入力のリテラルをそのまま出す（1.0 は 1.0、1.50 は 1.50）
//
// **指数表記だけは jq と違う。** jq は 1e3 を 1E+3、1.5e-3 を 0.0015 へ
// 再整形するが、ここは入力のまま出す。設定ファイルに指数表記は現れないので
// 実害が無く、jq の丸め規則を推測で再実装するほうが危険。
func Canonical(in []byte) (string, error) {
	dec := json.NewDecoder(bytes.NewReader(in))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return "", fmt.Errorf("JSON として読めない: %w", err)
	}
	// 末尾にゴミが続いていないか（jq もエラーにする）
	if dec.More() {
		return "", fmt.Errorf("JSON の後ろに余分な内容がある")
	}

	var b strings.Builder
	writeValue(&b, v, 0)
	b.WriteString("\n")
	return b.String(), nil
}

func writeValue(b *strings.Builder, v any, depth int) {
	pad := strings.Repeat("  ", depth)
	inner := strings.Repeat("  ", depth+1)

	switch t := v.(type) {
	case map[string]any:
		if len(t) == 0 {
			b.WriteString("{}")
			return
		}
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		b.WriteString("{\n")
		for i, k := range keys {
			b.WriteString(inner)
			writeJSONString(b, k)
			b.WriteString(": ")
			writeValue(b, t[k], depth+1)
			if i < len(keys)-1 {
				b.WriteString(",")
			}
			b.WriteString("\n")
		}
		b.WriteString(pad + "}")
	case []any:
		if len(t) == 0 {
			b.WriteString("[]")
			return
		}
		b.WriteString("[\n")
		for i, e := range t {
			b.WriteString(inner)
			writeValue(b, e, depth+1)
			if i < len(t)-1 {
				b.WriteString(",")
			}
			b.WriteString("\n")
		}
		b.WriteString(pad + "]")
	case string:
		writeJSONString(b, t)
	case json.Number:
		b.WriteString(t.String())
	case bool:
		if t {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	default:
		b.WriteString("null")
	}
}

func writeJSONString(b *strings.Builder, s string) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(s)
	b.WriteString(strings.TrimSuffix(buf.String(), "\n"))
}
