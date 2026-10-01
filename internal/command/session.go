package command

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/rhi222/dotfiles/internal/session"
)

const sessionUsage = `使い方: dotctl session nvim-plan --markers DIR --panes FILE --socket PATH [--focused ID] [--legacy]

  Herdrのpane一覧とnvimのprocess markerから、安全な復元計画をJSONで出す。
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
