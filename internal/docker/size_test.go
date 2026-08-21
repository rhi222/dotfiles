package docker

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
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

func TestFormatBytes(t *testing.T) {
	tests := []struct {
		in   int64
		want string
	}{
		{0, "0B"},
		{1, "1B"},
		{999, "999B"},
		{1000, "1kB"},
		{1234, "1.2kB"},
		{1500, "1.5kB"},
		{1000000, "1MB"},
		{12000000000, "12GB"},
		{5368709120, "5.4GB"},
		{1099511627776, "1.1TB"},
		{1500000000000, "1.5TB"},
		// **1TB の境界。** 999999999999 は GB のまま（1000GB と出る）
		{999999999999, "1000GB"},
	}
	for _, tt := range tests {
		if got := FormatBytes(tt.in); got != tt.want {
			t.Errorf("FormatBytes(%d) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

// **fish 版と同じ表記になることを実物で確かめる。** `math -s1` は末尾の 0 を
// 落とし（12.0 は 12）、偶数丸めをする（1.25 は 1.2、1.35 は 1.4）。
// この2つは推測で書くと外れる。
func TestFormatBytesMatchesFish(t *testing.T) {
	if testing.Short() {
		t.Skip("fish を起動するので -short では飛ばす")
	}
	fishBin, err := exec.LookPath("fish")
	if err != nil {
		t.Skip("fish が無い")
	}
	helper := filepath.Join(repoRoot(t), ".config", "fish", "my", "functions",
		"__docker_clean_format_bytes.fish")
	if _, serr := os.Stat(helper); serr != nil {
		t.Skip("fish 版が無い（移行済み）")
	}

	values := []int64{
		0, 1, 999, 1000, 1001, 1234, 1250, 1350, 1500, 9999,
		1000000, 1500000, 12000000000, 5368709120,
		999999999999, 1099511627776, 1500000000000, 1234567890123,
	}
	var script strings.Builder
	fmt.Fprintf(&script, "source %s\n", helper)
	for _, v := range values {
		fmt.Fprintf(&script, "__docker_clean_format_bytes %d\n", v)
	}

	out, err := exec.Command(fishBin, "-c", script.String()).Output()
	if err != nil {
		t.Fatalf("fish: %v", err)
	}
	lines := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	if len(lines) != len(values) {
		t.Fatalf("fish の出力行数 = %d, want %d", len(lines), len(values))
	}
	for i, v := range values {
		if got := FormatBytes(v); got != lines[i] {
			t.Errorf("FormatBytes(%d) = %q, fish = %q", v, got, lines[i])
		}
	}
}

// SizeToBytes も fish 版と一致すること。
func TestSizeToBytesMatchesFish(t *testing.T) {
	if testing.Short() {
		t.Skip("fish を起動するので -short では飛ばす")
	}
	fishBin, err := exec.LookPath("fish")
	if err != nil {
		t.Skip("fish が無い")
	}
	helper := filepath.Join(repoRoot(t), ".config", "fish", "my", "functions",
		"__docker_clean_size_to_bytes.fish")
	if _, serr := os.Stat(helper); serr != nil {
		t.Skip("fish 版が無い（移行済み）")
	}

	cases := [][]string{
		{"512B"},
		{"4.128kB"},
		{"577.8MB*"},
		{"12.53GB (51%)"},
		{"1KiB"},
		{"1MiB"},
		{"1kB", "2kB", "3MB"},
		{"0B"},
	}
	var script strings.Builder
	fmt.Fprintf(&script, "source %s\n", helper)
	for _, c := range cases {
		fmt.Fprintf(&script, "__docker_clean_size_to_bytes")
		for _, s := range c {
			fmt.Fprintf(&script, " %q", s)
		}
		fmt.Fprintln(&script)
	}

	out, err := exec.Command(fishBin, "-c", script.String()).Output()
	if err != nil {
		t.Fatalf("fish: %v\n%s", err, script.String())
	}
	lines := strings.Split(strings.TrimSuffix(string(out), "\n"), "\n")
	if len(lines) != len(cases) {
		t.Fatalf("行数 = %d, want %d（%q）", len(lines), len(cases), out)
	}
	for i, c := range cases {
		want, perr := strconv.ParseInt(strings.TrimSpace(lines[i]), 10, 64)
		if perr != nil {
			t.Fatalf("fish の出力が数値でない: %q", lines[i])
		}
		got, gerr := SizeToBytes(c...)
		if gerr != nil {
			t.Fatalf("SizeToBytes(%v): %v", c, gerr)
		}
		if got != want {
			t.Errorf("SizeToBytes(%v) = %d, fish = %d", c, got, want)
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

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Dir(filepath.Dir(wd))
}
