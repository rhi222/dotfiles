// Package docker は docker の不要リソースの掃除と、溜まり具合の通知を行う。
//
// **稼働中コンテナは一切停止しない。** 一覧を表示するだけで、停止は手動判断。
// named volume も削除しない（DB データを守るため）。
package docker

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// sizeRe は docker が返す人間可読サイズ。
//
// `docker system df` / `docker images` / `docker buildx du` はサイズを
// `4.128kB` や `577.8MB*` のような文字列でしか返さず、**生バイト数の
// フィールドを持たない**。単位は SI（kB = 1000）。
var sizeRe = regexp.MustCompile(`^([0-9]+(?:\.[0-9]+)?)\s*([kKMGTP]?i?B)$`)

// parenRe は df の割合注記（`12.53GB (51%)` の括弧以降）。
var parenRe = regexp.MustCompile(`\s*\(.*$`)

var units = map[string]float64{
	"B":   1,
	"kB":  1000,
	"KB":  1000,
	"MB":  1000 * 1000,
	"GB":  1000 * 1000 * 1000,
	"TB":  1000 * 1000 * 1000 * 1000,
	"PB":  1000 * 1000 * 1000 * 1000 * 1000,
	"KiB": 1024,
	"MiB": 1024 * 1024,
	"GiB": 1024 * 1024 * 1024,
	"TiB": 1024 * 1024 * 1024 * 1024,
	"PiB": 1024 * 1024 * 1024 * 1024 * 1024,
}

// SizeToBytes は人間可読サイズをバイト数に変換して合算する。
//
// `*`（共有レイヤのマーク）と `(51%)`（df の割合注記）はどちらも数値としては
// 無視する。空文字は飛ばす。解釈できない文字列があればエラーを返す。
func SizeToBytes(raws ...string) (int64, error) {
	var total float64
	for _, raw := range raws {
		s := strings.TrimSpace(parenRe.ReplaceAllString(raw, ""))
		s = strings.Trim(s, "*")
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		m := sizeRe.FindStringSubmatch(s)
		if m == nil {
			return 0, fmt.Errorf("解釈できないサイズ: %s", raw)
		}
		n, err := strconv.ParseFloat(m[1], 64)
		if err != nil {
			return 0, fmt.Errorf("解釈できないサイズ: %s", raw)
		}
		mult, ok := units[m[2]]
		if !ok {
			return 0, fmt.Errorf("未知の単位: %s", raw)
		}
		total += n * mult
	}
	return int64(math.Round(total)), nil
}

// SizeToBytesOrZero は解釈できないときに 0 を返す版。
//
// **呼び出し側が数値として扱うので、曖昧にしない。** Shell 版も
// `or set x 0` で同じことをしている。
func SizeToBytesOrZero(raws ...string) int64 {
	n, err := SizeToBytes(raws...)
	if err != nil {
		return 0
	}
	return n
}

// FormatBytes はバイト数を人間可読にする（SI 単位、小数1桁）。
func FormatBytes(b int64) string {
	if b < 0 {
		b = 0
	}
	switch {
	case b >= 1000*1000*1000*1000:
		return trimZero(float64(b)/1e12) + "TB"
	case b >= 1000*1000*1000:
		return trimZero(float64(b)/1e9) + "GB"
	case b >= 1000*1000:
		return trimZero(float64(b)/1e6) + "MB"
	case b >= 1000:
		return trimZero(float64(b)/1e3) + "kB"
	default:
		return strconv.FormatInt(b, 10) + "B"
	}
}

// trimZero は fish の `math -s1` と同じ表記にする。
//
// **fish の `math -s1` は末尾の 0 を落とす**（12.0 は "12"）。%.1f のままだと
// "12.0GB" になって Shell 版と食い違う。
func trimZero(f float64) string {
	s := strconv.FormatFloat(f, 'f', 1, 64)
	s = strings.TrimSuffix(s, ".0")
	return s
}
