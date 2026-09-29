// Package nodemodules は使っていない repository の node_modules を洗い出して掃除する。
//
// **「使っていない」は commit と install の両方が古いこと。** commit しないで
// 参照だけしている repository を消さないよう、install 時刻も見る。
// git 管理外は古さを判定できないので消さない。
package nodemodules

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Config は掃除1回分の設定。
type Config struct {
	Roots []string
	// Days より長く commit も install も無いものを候補にする。
	Days int
	Now  time.Time
	// Execute が偽なら何も削除しない（既定）。
	Execute bool
	// HeadTime は dir を含む git worktree の HEAD commit 時刻を返す。
	// nil なら git に聞く。git 管理外なら ok が偽。
	HeadTime func(ctx context.Context, dir string) (time.Time, bool)
}

// IO は出力先。
type IO struct {
	Stdout io.Writer
	Stderr io.Writer
}

// installMarkers は install のたびに書き直されるファイル。dir の mtime は
// トップレベルの増減でしか変わらないので、これらの時刻も見る。
var installMarkers = []string{".package-lock.json", ".modules.yaml", ".yarn-integrity", ".yarn-state.yml"}

// IsStale は commit と install の両方が Days より古いかを返す。
func IsStale(now time.Time, days int, head, installed time.Time) bool {
	cutoff := now.AddDate(0, 0, -days)
	return head.Before(cutoff) && installed.Before(cutoff)
}

// Run は候補を表示し、Execute なら削除する。
func Run(ctx context.Context, r execx.Runner, cfg Config, w IO) int {
	out, errw := w.Stdout, w.Stderr
	headTime := cfg.HeadTime
	if headTime == nil {
		headTime = func(ctx context.Context, dir string) (time.Time, bool) { return gitHeadTime(ctx, r, dir) }
	}

	mode := "DRY-RUN（削除しません）"
	if cfg.Execute {
		mode = "EXECUTE（実削除）"
	}
	fmt.Fprintf(out, "node_modules cleanup  mode: %s  基準: commit も install も %d 日以上前\n", mode, cfg.Days)

	count, totalKB, pnpmRemoved := 0, 0, false
	for _, nm := range find(cfg.Roots) {
		head, ok := headTime(ctx, filepath.Dir(nm))
		if !ok {
			fmt.Fprintf(out, "  [SKIP] git 管理外のため判定しない: %s\n", nm)
			continue
		}
		if !IsStale(cfg.Now, cfg.Days, head, installedAt(nm)) {
			continue
		}
		kb := sizeKB(ctx, r, nm)
		count++
		totalKB += kb
		fmt.Fprintf(out, "  [DELETE] %6s  %s  %s\n", human(kb), head.Format("2006-01-02"), nm)
		if !cfg.Execute {
			continue
		}
		isPnpm := fileExists(filepath.Join(nm, ".modules.yaml"))
		if err := os.RemoveAll(nm); err != nil {
			fmt.Fprintf(errw, "    削除に失敗しました: %v\n", err)
			continue
		}
		pnpmRemoved = pnpmRemoved || isPnpm
	}

	// pnpm の node_modules は store への hardlink。store から外さないと容量が戻らない
	if pnpmRemoved {
		if res, err := r.Run(ctx, execx.Cmd{Name: "pnpm", Args: []string{"store", "prune"}}); err != nil || !res.OK() {
			fmt.Fprintln(errw, "  pnpm store prune に失敗しました")
		} else {
			fmt.Fprintln(out, "  pnpm store prune を実行しました")
		}
	}

	// daily-update が拾う契約行。表示の体裁を変えてもここは変えない
	fmt.Fprintf(out, "node-modules-cleanup: CANDIDATES=%d SIZE_MB=%d\n", count, totalKB/1024)
	if !cfg.Execute && count > 0 {
		fmt.Fprintln(out, "これは dry-run です。削除するには --execute を付けて再実行してください。")
		fmt.Fprintln(out, "（pnpm は store と hardlink を共有するため、実際に空く量は表示より小さいことがあります）")
	}
	return 0
}

// find は roots 配下の node_modules を返す。node_modules と .git の中には入らない。
func find(roots []string) []string {
	var found []string
	for _, root := range roots {
		_ = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil || !d.IsDir() {
				return nil
			}
			switch d.Name() {
			case ".git":
				return filepath.SkipDir
			case "node_modules":
				found = append(found, p)
				return filepath.SkipDir
			}
			return nil
		})
	}
	return found
}

func installedAt(nm string) time.Time {
	var latest time.Time
	for _, p := range append([]string{nm}, markerPaths(nm)...) {
		if st, err := os.Stat(p); err == nil && st.ModTime().After(latest) {
			latest = st.ModTime()
		}
	}
	return latest
}

func markerPaths(nm string) []string {
	ps := make([]string, len(installMarkers))
	for i, m := range installMarkers {
		ps[i] = filepath.Join(nm, m)
	}
	return ps
}

func gitHeadTime(ctx context.Context, r execx.Runner, dir string) (time.Time, bool) {
	res, err := r.Run(ctx, execx.Cmd{Name: "git", Args: []string{"-C", dir, "log", "-1", "--format=%ct"}})
	if err != nil || !res.OK() {
		return time.Time{}, false
	}
	sec, err := strconv.ParseInt(strings.TrimSpace(res.Stdout), 10, 64)
	if err != nil {
		return time.Time{}, false
	}
	return time.Unix(sec, 0), true
}

func sizeKB(ctx context.Context, r execx.Runner, p string) int {
	res, err := r.Run(ctx, execx.Cmd{Name: "du", Args: []string{"-sk", p}})
	if err != nil || !res.OK() {
		return 0
	}
	f := strings.Fields(res.Stdout)
	if len(f) == 0 {
		return 0
	}
	kb, _ := strconv.Atoi(f[0])
	return kb
}

func human(kb int) string {
	if kb >= 1024*1024 {
		return fmt.Sprintf("%.1fG", float64(kb)/1024/1024)
	}
	return fmt.Sprintf("%dM", kb/1024)
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
