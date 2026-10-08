package command

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/rhi222/dotfiles/internal/followup"
)

const followupUsage = `使い方:
  dotctl followup targets --in <FILE|->
    Linear issueの配列からSlackスレを取り出し、targets.json を状態ディレクトリへ書く。
    stdoutにskill向けの読み取り指示（key, channel, thread_ts, oldest）をJSONで出す。
  dotctl followup apply --in <FILE|->
    skillが読んだ各スレの最新発言を前回状態と比べ、一覧md・状態・通知文を書く。
    stdoutに一覧mdのpathと、あれば通知文を出す。
`

func runFollowup(args []string, env Env) int {
	if len(args) == 0 || (args[0] != "apply" && args[0] != "targets") || env.FollowupStateDir == "" {
		fmt.Fprint(env.Stderr, followupUsage)
		return 2
	}
	sub := args[0]
	fs := flag.NewFlagSet(sub, flag.ContinueOnError)
	fs.SetOutput(env.Stderr)
	inPath := fs.String("in", "", "input JSON file, or - for stdin")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if fs.NArg() != 0 || *inPath == "" {
		fmt.Fprint(env.Stderr, followupUsage)
		return 2
	}
	var b []byte
	var err error
	if *inPath == "-" {
		if env.Stdin == nil {
			fmt.Fprintf(env.Stderr, "dotctl followup %s: 標準入力がない\n", sub)
			return 2
		}
		b, err = io.ReadAll(env.Stdin)
	} else {
		b, err = os.ReadFile(*inPath)
	}
	if err == nil {
		if sub == "targets" {
			err = followupTargets(b, env)
		} else {
			err = followupApply(b, env)
		}
	}
	if err != nil {
		fmt.Fprintf(env.Stderr, "dotctl followup %s: %v\n", sub, err)
		return 1
	}
	return 0
}

func followupTargets(b []byte, env Env) error {
	var issues []followup.LinearIssue
	if err := json.Unmarshal(b, &issues); err != nil {
		return fmt.Errorf("入力が不正: %w", err)
	}
	// null は Unmarshal を通るが、対象0本として状態を全消去してしまう
	if issues == nil {
		return fmt.Errorf("入力が不正: issueの配列でない")
	}
	st, _, err := followup.Load(env.FollowupStateDir)
	if err != nil {
		return fmt.Errorf("状態を読めない: %w", err)
	}
	ts := followup.ExtractTargets(issues)
	if err := followup.SaveTargets(env.FollowupStateDir, ts); err != nil {
		return err
	}
	return json.NewEncoder(env.Stdout).Encode(followup.Prompts(ts, st))
}

func followupApply(b []byte, env Env) error {
	in, err := followup.ParseInput(b)
	if err != nil {
		return fmt.Errorf("入力が不正: %w", err)
	}
	ts, err := followup.LoadTargets(env.FollowupStateDir)
	if err != nil {
		return err
	}
	prev, first, err := followup.Load(env.FollowupStateDir)
	if err != nil {
		return fmt.Errorf("状態を読めない: %w", err)
	}
	r, err := followup.Apply(in, ts, prev, first)
	if err != nil {
		return fmt.Errorf("入力が不正: %w", err)
	}
	loc := env.Location
	if loc == nil {
		loc = time.Local
	}
	if err := followup.Save(env.FollowupStateDir, r, followup.Render(r, time.Now().In(loc))); err != nil {
		return err
	}
	fmt.Fprintln(env.Stdout, filepath.Join(env.FollowupStateDir, "latest.md"))
	if n := followup.Notice(r); n != "" {
		fmt.Fprintln(env.Stdout, n)
	}
	return nil
}
