package worktree

import (
	"context"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// entry は porcelain から読んだ worktree 1件（判定に要る事実の一部）。
type entry struct {
	Path        string
	Branch      string
	Locked      bool
	LockDetail  string
	Prunable    bool
	PruneDetail string
}

// parseWorktrees は `git worktree list --porcelain` の出力を解析する。
// main worktree は除外する。
//
// **detached の空 branch を保つのが要点。** Shell 版は一度 TSV へ落として
// 読み直していたが、TAB は IFS の空白文字なので連続タブが1区切りに畳まれ、
// 空 branch フィールドが消えて以降のフィールドがずれた。構造体のまま持てば
// その失敗の余地が無い。
func parseWorktrees(porcelain, mainPath string) []entry {
	var out []entry
	var cur entry
	have := false

	flush := func() {
		if have && cur.Path != "" && normPath(cur.Path) != normPath(mainPath) {
			out = append(out, cur)
		}
		cur = entry{}
		have = false
	}

	for _, line := range strings.Split(porcelain, "\n") {
		switch {
		case strings.HasPrefix(line, "worktree "):
			// 直前のレコードを確定してから次を始める。**空行が無い入力でも
			// 取りこぼさない**（コマンド置換で末尾改行が落ちた形）
			flush()
			cur.Path = strings.TrimPrefix(line, "worktree ")
			have = true
		case strings.HasPrefix(line, "branch refs/heads/"):
			cur.Branch = strings.TrimPrefix(line, "branch refs/heads/")
		case line == "locked":
			cur.Locked = true
		case strings.HasPrefix(line, "locked "):
			cur.Locked = true
			cur.LockDetail = strings.TrimPrefix(line, "locked ")
		case line == "prunable":
			cur.Prunable = true
		case strings.HasPrefix(line, "prunable "):
			cur.Prunable = true
			cur.PruneDetail = strings.TrimPrefix(line, "prunable ")
		case line == "":
			flush()
		}
	}
	flush()
	return out
}

// normPath は比較用にパスを正規化する。
func normPath(p string) string {
	if p == "" {
		return ""
	}
	return filepath.Clean(strings.TrimSuffix(p, "/"))
}

// prState はブランチに対応する PR の状態を取得する。
//
// override が空でなければそれを実行する（Shell 版の
// WORKTREE_CLEANUP_PR_STATE_CMD と同じ差し替え口）。
//
// **取得できなかったときは PRUnavailable に倒す。** 判定不能を DELETE 側へ
// 倒さないため、呼び出し側はこれを KEEP の材料にする。
func prState(ctx context.Context, r execx.Runner, repo, branch, override string) PRState {
	var res execx.Result
	var err error

	if override != "" {
		res, err = r.Run(ctx, execx.Cmd{Name: override, Args: []string{repo, branch}})
	} else {
		res, err = r.Run(ctx, execx.Cmd{
			Name: "gh",
			Args: []string{
				"pr", "list", "--head", branch, "--state", "all",
				"--json", "number,state", "--limit", "1",
				"--jq", `if length == 0 then "NONE" else (.[0].state + " #" + (.[0].number | tostring)) end`,
			},
			Dir: repo,
		})
	}
	if err != nil || !res.OK() {
		return PRState{Kind: PRUnavailable}
	}

	raw := strings.TrimSpace(res.Stdout)
	switch {
	case raw == "":
		return PRState{Kind: PRUnavailable}
	case raw == "NONE":
		return PRState{Kind: PRNone, Raw: raw}
	case strings.HasPrefix(raw, "MERGED"):
		return PRState{Kind: PRMerged, Raw: raw}
	case strings.HasPrefix(raw, "CLOSED"):
		return PRState{Kind: PRClosed, Raw: raw}
	default:
		return PRState{Kind: PROpen, Raw: raw}
	}
}

// hasTrackedChanges は追跡ファイルに未コミット変更があるか。
//
// **未追跡ファイルは意図的に見ない。** dirty の実体が plans/ 等の使い捨て
// スクラッチ1件であることが多く、未追跡を dirty に含めるとマージ済み
// worktree の削除がほぼ全部ブロックされる。
func hasTrackedChanges(ctx context.Context, r execx.Runner, path string) bool {
	res, err := r.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"-C", path, "status", "--porcelain", "--untracked-files=no"},
	})
	if err != nil || !res.OK() {
		return false
	}
	return strings.TrimSpace(res.Stdout) != ""
}

// untrackedCount は未追跡ファイルの件数。測れなければ 0。
func untrackedCount(ctx context.Context, r execx.Runner, path string) int {
	res, err := r.Run(ctx, execx.Cmd{
		Name: "git", Args: []string{"-C", path, "status", "--porcelain", "--untracked-files=normal"},
	})
	if err != nil || !res.OK() {
		return 0
	}
	n := 0
	for _, line := range strings.Split(res.Stdout, "\n") {
		if strings.HasPrefix(line, "??") {
			n++
		}
	}
	return n
}

// mainWorktreePath は main worktree の正規化済みパスを返す。
//
// git-common-dir は <main worktree>/.git を指すので、その親が main worktree。
// **レコード順（git は main を先頭に出す）に依存しないためにこの方法を使う。**
func mainWorktreePath(ctx context.Context, r execx.Runner, repo string) (string, bool) {
	res, err := r.Run(ctx, execx.Cmd{
		Name: "git",
		Args: []string{"-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir"},
	})
	if err != nil || !res.OK() {
		return "", false
	}
	dir := strings.TrimSpace(res.Stdout)
	if dir == "" {
		return "", false
	}
	return normPath(filepath.Dir(dir)), true
}

// sizeKB はパスのサイズを KB で返す（測れなければ 0）。
func sizeKB(ctx context.Context, r execx.Runner, path string) int {
	res, err := r.Run(ctx, execx.Cmd{Name: "du", Args: []string{"-sk", path}})
	if err != nil || !res.OK() {
		return 0
	}
	fields := strings.Fields(res.Stdout)
	if len(fields) == 0 {
		return 0
	}
	n, err := strconv.Atoi(fields[0])
	if err != nil || n < 0 {
		return 0
	}
	return n
}
