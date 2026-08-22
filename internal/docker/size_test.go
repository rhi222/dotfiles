// Dockerのsize表記を境界値込みで正規化し、fish版と同じ表示幅・paddingを維持する。
package docker

import (
	"fmt"
	"os/exec"
	"strings"
	"testing"
)

func TestSizeToBytes(t *testing.T) {
	tests := []struct {
		name string
		in   []string
		want int64
	}{
		{"バイト", []string{"512B"}, 512},
		{"kB は SI（1000）", []string{"4.128kB"}, 4128},
		{"KB も受ける", []string{"2KB"}, 2000},
		{"MB", []string{"577.8MB"}, 577800000},
		{"GB", []string{"12.53GB"}, 12530000000},
		{"TB", []string{"1.5TB"}, 1500000000000},
		{"KiB は 1024", []string{"1KiB"}, 1024},
		{"MiB", []string{"1MiB"}, 1048576},
		{"GiB", []string{"1GiB"}, 1073741824},
		// **`*` は共有レイヤのマーク。** 数値としては無視する
		{"共有マークを落とす", []string{"577.8MB*"}, 577800000},
		// **`(51%)` は df の割合注記。** 同じく無視する
		{"割合注記を落とす", []string{"12.53GB (51%)"}, 12530000000},
		{"空文字は飛ばす", []string{"", "1kB", ""}, 1000},
		{"複数を合算する", []string{"1kB", "2kB", "3MB"}, 3003000},
		{"引数なしは 0", nil, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := SizeToBytes(tt.in...)
			if err != nil {
				t.Fatalf("SizeToBytes(%v): %v", tt.in, err)
			}
			if got != tt.want {
				t.Errorf("= %d, want %d", got, tt.want)
			}
		})
	}
}

func TestSizeToBytesRejectsGarbage(t *testing.T) {
	// **解釈できないものを 0 として飲み込まない。** 飲むと「回収見込み 0B」が
	// 出て、パース漏れに気付けなくなる
	for _, in := range []string{"N/A", "12", "12 bytes", "abcMB", "12XB"} {
		if _, err := SizeToBytes(in); err == nil {
			t.Errorf("%q を通してしまった", in)
		}
	}
	// OrZero 版は 0 を返す（呼び出し側が数値として扱う箇所で使う）
	if got := SizeToBytesOrZero("N/A"); got != 0 {
		t.Errorf("OrZero = %d, want 0", got)
	}
}

// 期待値は**fish の `math -s1` で実測したもの**。fish 版が消えた後もこの
// 表記を守るための golden。
//
// 推測で書くと外れる点が2つある。
//   - **末尾の 0 を落とす。** 12.0 は "12"（%.1f のままだと "12.0GB" になる）
//   - **偶数丸め。** 1.25 は 1.2、1.35 は 1.4（半数切り上げではない）
func TestFormatBytes(t *testing.T) {
	tests := []struct {
		in   int64
		want string
	}{
		{0, "0B"},
		{1, "1B"},
		{999, "999B"},
		{1000, "1kB"},
		{1001, "1kB"},
		{1234, "1.2kB"},
		// **偶数丸めの境界。** 1.25 -> 1.2、1.35 -> 1.4
		{1250, "1.2kB"},
		{1350, "1.4kB"},
		{1500, "1.5kB"},
		{9999, "10kB"},
		// **末尾の 0 を落とす。** 1MB / 12GB（1.0MB / 12.0GB ではない）
		{1000000, "1MB"},
		{1500000, "1.5MB"},
		{12000000000, "12GB"},
		{5368709120, "5.4GB"},
		// **1TB の境界。** 999999999999 は GB のまま（1000GB と出る）
		{999999999999, "1000GB"},
		{1099511627776, "1.1TB"},
		{1500000000000, "1.5TB"},
		{1234567890123, "1.2TB"},
	}
	for _, tt := range tests {
		if got := FormatBytes(tt.in); got != tt.want {
			t.Errorf("FormatBytes(%d) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

// --- 表示幅 ---

func TestDisplayWidth(t *testing.T) {
	tests := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"abc", 3},
		{"停止コンテナ", 12},
		{"未使用 image", 12},
		{"未使用 volume", 13},
		{"dangling image", 14},
		{"build cache", 11},
		{"（テスト）", 10},
		{"🗑", 2},
	}
	for _, tt := range tests {
		if got := DisplayWidth(tt.in); got != tt.want {
			t.Errorf("DisplayWidth(%q) = %d, want %d", tt.in, got, tt.want)
		}
	}
}

func TestPadRightMatchesFishStringPad(t *testing.T) {
	if testing.Short() {
		t.Skip("fish を起動するので -short では飛ばす")
	}
	fishBin, err := exec.LookPath("fish")
	if err != nil {
		t.Skip("fish が無い")
	}

	labels := []string{"停止コンテナ", "dangling image", "未使用 image", "未使用 volume", "build cache", "abc"}
	var script strings.Builder
	for _, l := range labels {
		fmt.Fprintf(&script, "printf '[%%s]\\n' (string pad -r -w 18 -- %q)\n", l)
	}
	out, err := exec.Command(fishBin, "-c", script.String()).Output()
	if err != nil {
		t.Fatalf("fish: %v", err)
	}
	lines := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	for i, l := range labels {
		want := lines[i]
		if got := "[" + PadRight(l, 18) + "]"; got != want {
			t.Errorf("PadRight(%q, 18) = %q, fish = %q", l, got, want)
		}
	}
}

func TestPadLeft(t *testing.T) {
	if got := PadLeft("3", 4); got != "   3" {
		t.Errorf("= %q", got)
	}
	if got := PadLeft("2461", 4); got != "2461" {
		t.Errorf("超過分は切らない: %q", got)
	}
}
