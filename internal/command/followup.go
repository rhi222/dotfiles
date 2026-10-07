package command

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/rhi222/dotfiles/internal/followup"
)

const followupUsage = `使い方:
  dotctl followup apply --in <FILE|->
    skillが集めた返事待ち・頼まれ事のJSONを前回状態と比べ、
    一覧md・状態・通知文を状態ディレクトリへ書く。stdoutに一覧mdのpathを出す。
`

func runFollowup(args []string, env Env) int {
	if len(args) == 0 || args[0] != "apply" {
		fmt.Fprint(env.Stderr, followupUsage)
		return 2
	}
	fs := flag.NewFlagSet("apply", flag.ContinueOnError)
	fs.SetOutput(env.Stderr)
	inPath := fs.String("in", "", "input JSON file, or - for stdin")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if fs.NArg() != 0 || *inPath == "" || env.FollowupStateDir == "" {
		fmt.Fprint(env.Stderr, followupUsage)
		return 2
	}
	var b []byte
	var err error
	if *inPath == "-" {
		if env.Stdin == nil {
			fmt.Fprintln(env.Stderr, "dotctl followup apply: 標準入力がない")
			return 2
		}
		b, err = io.ReadAll(env.Stdin)
	} else {
		b, err = os.ReadFile(*inPath)
	}
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl followup apply: %v\n", err)
		return 1
	}
	in, err := followup.ParseInput(b)
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl followup apply: 入力が不正: %v\n", err)
		return 1
	}
	prev, first, err := followup.Load(env.FollowupStateDir)
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl followup apply: 状態を読めない: %v\n", err)
		return 1
	}
	loc := env.Location
	if loc == nil {
		loc = time.Local
	}
	r := followup.Apply(in, prev, first)
	md := followup.Render(r, in.GeneratedAt.In(loc))
	if err := followup.Save(env.FollowupStateDir, r, md); err != nil {
		fmt.Fprintf(env.Stderr, "dotctl followup apply: %v\n", err)
		return 1
	}
	fmt.Fprintln(env.Stdout, filepath.Join(env.FollowupStateDir, "latest.md"))
	if n := followup.Notice(r); n != "" {
		fmt.Fprintln(env.Stdout, n)
	}
	return 0
}
