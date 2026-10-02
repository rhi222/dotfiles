package sessiondigest

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Options struct {
	ClaudeRoot   string // ~/.claude
	CodexRoot    string // ~/.codex
	Day          Day
	MinUserTurns int
}

type Result struct {
	Sessions   []Session
	Skipped    int // 読めなかった行の合計
	Unreadable int // 開けなかった・読み切れなかったファイルの数
}

type parser func(io.Reader, Day) (Session, int, error)

// Collect は当日に発言のある session を開始時刻順に返す。
//
// Claude は projects/<slug>/*.jsonl だけを見る（subagents/ は1段深いので glob に掛からない）。
// Codex は開始日のディレクトリに置かれたまま resume で追記されるので、全日付を glob し、
// 当日に更新されていないファイルは parseFile の mtime 判定で開かずに飛ばす。
func Collect(opt Options) (Result, error) {
	claude, _ := filepath.Glob(filepath.Join(opt.ClaudeRoot, "projects", "*", "*.jsonl"))
	codex, _ := filepath.Glob(filepath.Join(opt.CodexRoot, "sessions", "*", "*", "*", "rollout-*.jsonl"))

	var res Result
	for _, src := range []struct {
		files  []string
		parse  parser
		fileID bool
	}{{claude, ParseClaude, true}, {codex, ParseCodex, false}} {
		for _, path := range src.files {
			s, skipped, err := parseFile(path, opt.Day, src.parse)
			// 1本読めないだけで他の session まで出なくなるのを避ける。件数は呼び出し側が報告する
			if err != nil {
				res.Unreadable++
				continue
			}
			// Claude はファイル名の uuid が session の正。resume/fork したログは
			// 先頭行の sessionId が元 session のままで、digest 名が衝突しうる。
			if src.fileID {
				s.SessionID = strings.TrimSuffix(filepath.Base(path), ".jsonl")
			}
			res.Skipped += skipped
			if len(s.Turns) > 0 && s.UserTurns() >= opt.MinUserTurns {
				res.Sessions = append(res.Sessions, s)
			}
		}
	}
	sort.SliceStable(res.Sessions, func(i, j int) bool {
		return res.Sessions[i].StartedAt().Before(res.Sessions[j].StartedAt())
	})
	return res, nil
}

// parseFile は当日より前に更新が止まったファイルを開かずに飛ばす（283MB 全部は読まない）。
// glob 後に消えたファイル（rollout の書き換え中など）は無かったことにする。
func parseFile(path string, day Day, parse parser) (Session, int, error) {
	info, err := os.Stat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Session{}, 0, nil
	}
	if err != nil {
		return Session{}, 0, err
	}
	if info.ModTime().Before(day.Start) {
		return Session{}, 0, nil
	}
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Session{}, 0, nil
	}
	if err != nil {
		return Session{}, 0, err
	}
	defer f.Close()
	s, skipped, err := parse(f, day)
	if s.SessionID == "" {
		s.SessionID = strings.TrimSuffix(filepath.Base(path), ".jsonl")
	}
	return s, skipped, err
}
