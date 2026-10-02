package command

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/rhi222/dotfiles/internal/session"
	"github.com/rhi222/dotfiles/internal/sessiondigest"
)

const sessionUsage = `使い方:
  dotctl session nvim-plan --markers DIR --panes FILE --socket PATH [--focused ID] [--legacy]
    Herdrのpane一覧とnvimのprocess markerから、安全な復元計画をJSONで出す。
  dotctl session digest --date YYYY-MM-DD --out-dir DIR [--min-user-turns N]
    当日のClaude/Codex sessionから本文だけを取り出し、sessionごとのMarkdownをDIRへ書く。
    stdoutには索引をJSON Linesで出す。
  dotctl session digest-clean DIR
    digestが書いたファイルだけを消し、空になったDIRを外す。
`

func runSession(args []string, env Env) int {
	if len(args) == 0 {
		fmt.Fprint(env.Stderr, sessionUsage)
		return 2
	}
	switch args[0] {
	case "-h", "--help":
		fmt.Fprint(env.Stdout, sessionUsage)
		return 0
	case "nvim-plan":
		return runNvimPlan(args[1:], env)
	case "digest":
		return runSessionDigest(args[1:], env)
	case "digest-clean":
		if len(args) != 2 {
			fmt.Fprint(env.Stderr, sessionUsage)
			return 2
		}
		if err := sessiondigest.CleanDigests(args[1]); err != nil {
			fmt.Fprintf(env.Stderr, "dotctl session digest-clean: %v\n", err)
			return 1
		}
		return 0
	default:
		fmt.Fprintf(env.Stderr, "dotctl session: 知らないサブコマンド: %s\n\n%s", args[0], sessionUsage)
		return 2
	}
}

func runNvimPlan(args []string, env Env) int {
	fs := flag.NewFlagSet("nvim-plan", flag.ContinueOnError)
	fs.SetOutput(env.Stderr)
	markers := fs.String("markers", "", "marker directory")
	panes := fs.String("panes", "", "pane list JSON file")
	socket := fs.String("socket", "", "Herdr socket path")
	focused := fs.String("focused", "", "focused workspace id")
	legacy := fs.Bool("legacy", false, "accept version 1 markers")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() != 0 || *markers == "" || *panes == "" || *socket == "" {
		fmt.Fprint(env.Stderr, sessionUsage)
		return 2
	}
	b, err := os.ReadFile(*panes)
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session nvim-plan: %v\n", err)
		return 1
	}
	plan, err := session.BuildPlan(session.PlanOptions{
		MarkerDir: *markers, PaneJSON: b, SocketPath: *socket,
		FocusedWorkspace: *focused, AllowLegacy: *legacy,
	})
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session nvim-plan: %v\n", err)
		return 1
	}
	enc := json.NewEncoder(env.Stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(plan); err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session nvim-plan: %v\n", err)
		return 1
	}
	return 0
}

func runSessionDigest(args []string, env Env) int {
	fs := flag.NewFlagSet("digest", flag.ContinueOnError)
	fs.SetOutput(env.Stderr)
	date := fs.String("date", "", "YYYY-MM-DD")
	outDir := fs.String("out-dir", "", "digest output directory")
	minTurns := fs.Int("min-user-turns", 3, "skip sessions with fewer user turns")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() != 0 || *date == "" || *outDir == "" {
		fmt.Fprint(env.Stderr, sessionUsage)
		return 2
	}
	loc := env.Location
	if loc == nil {
		loc = time.Local
	}
	day, err := sessiondigest.NewDay(*date, loc)
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session digest: --date: %v\n", err)
		return 2
	}
	res, err := sessiondigest.Collect(sessiondigest.Options{
		ClaudeRoot: env.SessionDigestClaudeRoot, CodexRoot: env.SessionDigestCodexRoot,
		Day: day, MinUserTurns: *minTurns,
	})
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session digest: %v\n", err)
		return 1
	}
	if err := os.MkdirAll(*outDir, 0o700); err != nil {
		fmt.Fprintf(env.Stderr, "dotctl session digest: %v\n", err)
		return 1
	}
	enc := json.NewEncoder(env.Stdout)
	enc.SetEscapeHTML(false)
	for _, s := range res.Sessions {
		e, err := sessiondigest.WriteDigest(*outDir, s)
		if err != nil {
			fmt.Fprintf(env.Stderr, "dotctl session digest: %v\n", err)
			return 1
		}
		if err := enc.Encode(e); err != nil {
			fmt.Fprintf(env.Stderr, "dotctl session digest: %v\n", err)
			return 1
		}
	}
	if res.Skipped > 0 || res.Unreadable > 0 {
		fmt.Fprintf(env.Stderr, "session-digest: SKIPPED=%d UNREADABLE=%d\n", res.Skipped, res.Unreadable)
	}
	return 0
}
