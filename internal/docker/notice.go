package docker

import (
	"fmt"
	"strings"
)

// Reclaimable は回収可能量を掃除モードで分けたもの。
type Reclaimable struct {
	// Light は軽掃除の prune がそのまま回収する量。
	Light int64
	// Heavy は重掃除でしか消えない分を含む合計。
	Heavy int64
}

// SplitReclaimable は df の Reclaimable を軽掃除と重掃除に振り分ける。
//
// **`Images` を軽掃除の根拠にしてはいけない。** df の Images Reclaimable は
// 「どのコンテナからも参照されていない image」の量で、dangling かどうかは
// 問わない。軽掃除の `image prune -f` は dangling だけを消すため、ここを
// 軽掃除の根拠にすると「dclean しても通知が消えない」状態になる（実際になった）。
//
// 一方 Containers / Local Volumes / Build Cache の Reclaimable は軽掃除の
// prune がそのまま回収する量に対応する（実測で prune 後に 0B になる）。
func SplitReclaimable(s *Stats) Reclaimable {
	var light, heavyOnly []string
	for _, e := range s.DF {
		if e.Reclaimable == "" {
			continue
		}
		if e.Type == "Images" {
			heavyOnly = append(heavyOnly, e.Reclaimable)
			continue
		}
		light = append(light, e.Reclaimable)
	}
	l := SizeToBytesOrZero(light...)
	return Reclaimable{Light: l, Heavy: l + SizeToBytesOrZero(heavyOnly...)}
}

// Notice は起動時通知の1行を組み立てる。
//
// 閾値未満で長時間稼働も無ければ空文字（＝何も出さない）。
//
// **案内するコマンドは、その量を実際に回収できるモードに合わせる。** 軽掃除で
// 回収できない量を `dclean` で案内すると、実行しても通知が消えない。
func Notice(s *Stats, cfg Config, dirExists func(string) bool) string {
	if s == nil {
		return ""
	}
	rec := SplitReclaimable(s)
	long := LongRunning(s, cfg, false)

	orphan := 0
	for _, c := range long {
		if ContainerKind(c.ComposeProject, c.ComposeDir, dirExists) == Orphan {
			orphan++
		}
	}

	thr := int64(cfg.SizeThresholdGB * 1e9)
	sizeMsg := ""
	cmd := "dclean"
	switch {
	case rec.Light >= thr:
		sizeMsg = FormatBytes(rec.Light) + " 回収可能"
	case rec.Heavy >= thr:
		sizeMsg = FormatBytes(rec.Heavy) + " 回収可能（未使用 image 中心）"
		cmd = "dclean -a"
	}

	if sizeMsg == "" && len(long) == 0 {
		return ""
	}

	var parts []string
	if sizeMsg != "" {
		parts = append(parts, sizeMsg)
	}
	if len(long) > 0 {
		// 閾値の表記は Shell 版に合わせる（12h超稼働 3件）
		longMsg := fmt.Sprintf("%sh超稼働 %d件", trimZero(cfg.UptimeThresholdH), len(long))
		if orphan > 0 {
			longMsg += fmt.Sprintf("（orphan %d）", orphan)
		}
		parts = append(parts, longMsg)
	}
	if sizeMsg == "" {
		cmd = "dclean --status"
	}

	return fmt.Sprintf("🗑  docker: %s  → %s", strings.Join(parts, " / "), cmd)
}
