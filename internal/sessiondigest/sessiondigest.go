// Package sessiondigest は Claude Code / Codex の session ログから、
// 人と agent が交わした本文だけを日付で切り出す。kb-harvest skill の入力になる。
//
// **tool の入出力と harness の注入文は捨てる。** 残すと1 session が数十万字になり、
// 判定する subagent が注入文やコマンド出力を知識と取り違える。
package sessiondigest

import (
	"bufio"
	"bytes"
	"io"
	"strings"
	"time"
)

type Turn struct {
	Role string
	Text string
	At   time.Time
}

type Session struct {
	Source    string
	SessionID string
	Cwd       string
	Turns     []Turn
}

func (s Session) UserTurns() int {
	n := 0
	for _, t := range s.Turns {
		if t.Role == "user" {
			n++
		}
	}
	return n
}

func (s Session) StartedAt() time.Time {
	if len(s.Turns) == 0 {
		return time.Time{}
	}
	return s.Turns[0].At
}

// Day は [Start, End) のローカル日付。
type Day struct{ Start, End time.Time }

func NewDay(date string, loc *time.Location) (Day, error) {
	start, err := time.ParseInLocation("2006-01-02", date, loc)
	if err != nil {
		return Day{}, err
	}
	return Day{Start: start, End: start.AddDate(0, 0, 1)}, nil
}

func (d Day) Contains(t time.Time) bool { return !t.Before(d.Start) && t.Before(d.End) }

// local は時刻を日付判定と同じタイムゾーンへ寄せる。digest の表示をローカル時刻にするため。
func (d Day) local(t time.Time) time.Time { return t.In(d.Start.Location()) }

// ponytail: 先頭一致の判定。"<" で始まる本文（HTMLの貼り付けなど）も落ちる。
// 取りこぼしが問題になったら、既知のタグ名の一覧に絞る。
var injectedPrefixes = []string{
	"<",
	"# AGENTS.md instructions",
	"Base directory for this skill:",
	"Caveat:",
}

// keep は本文として残すかを決める。注入文の判定は user ロールだけに掛ける。
func keep(role, text string) bool {
	t := strings.TrimSpace(text)
	if t == "" {
		return false
	}
	if role != "user" {
		return true
	}
	for _, p := range injectedPrefixes {
		if strings.HasPrefix(t, p) {
			return false
		}
	}
	return true
}

// eachLine は空でない行を1行ずつ f に渡し、f が失敗した行の数を返す。
// **bufio.Scanner を使わない。** tool_result を含む行は64KBの上限を超える。
func eachLine(r io.Reader, f func([]byte) error) (int, error) {
	br := bufio.NewReader(r)
	skipped := 0
	for {
		line, err := br.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 && f(line) != nil {
			skipped++
		}
		if err == io.EOF {
			return skipped, nil
		}
		if err != nil {
			return skipped, err
		}
	}
}
