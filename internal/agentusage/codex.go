package agentusage

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// weeklyWindowMinutes 以上の窓を「weekly」とみなす（10080分 = 7日）。
const weeklyWindowMinutes = 10080

// codexRecentDays は rollout を遡る日数。codex を数日使っていなければ
// %も動いていないので、深追いせずキャッシュ無し（欄ごと非表示）に倒す。
const codexRecentDays = 3

// FetchCodex は ~/.codex/sessions の rollout JSONL から weekly レート上限を取る。
//
// rollout には API レスポンス由来の rate_limits スナップショットが残るので、
// ネットワークを叩かずに済む。鮮度は「最後に codex を使った時点」だが、
// 使っていなければ%も動かないので実用上は正確なまま。
func FetchCodex(sessionsDir string, now time.Time) (*Side, error) {
	files, err := recentRollouts(sessionsDir)
	if err != nil {
		return nil, err
	}
	for _, path := range files {
		w, ok := lastRateLimits(path)
		if !ok {
			continue
		}
		return &Side{FetchedAt: now.Unix(), Weekly: w}, nil
	}
	return nil, fmt.Errorf("直近 %d 日の rollout に rate_limits が無い", codexRecentDays)
}

// recentRollouts は直近の日付ディレクトリから rollout を mtime 降順で集める。
// sessions/ は YYYY/MM/DD 構造なので、全走査せず日付ディレクトリを数個に絞る。
func recentRollouts(root string) ([]string, error) {
	var days []string // "YYYY/MM/DD" 相対パス
	years, err := sortedDirNames(root)
	if err != nil {
		return nil, err
	}
	// 新しい順に辿り、日付ディレクトリを codexRecentDays 個だけ集める
	for i := len(years) - 1; i >= 0 && len(days) < codexRecentDays; i-- {
		months, _ := sortedDirNames(filepath.Join(root, years[i]))
		for j := len(months) - 1; j >= 0 && len(days) < codexRecentDays; j-- {
			dayNames, _ := sortedDirNames(filepath.Join(root, years[i], months[j]))
			for k := len(dayNames) - 1; k >= 0 && len(days) < codexRecentDays; k-- {
				days = append(days, filepath.Join(years[i], months[j], dayNames[k]))
			}
		}
	}
	type fileInfo struct {
		path  string
		mtime time.Time
	}
	var files []fileInfo
	for _, d := range days {
		entries, err := os.ReadDir(filepath.Join(root, d))
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasPrefix(e.Name(), "rollout-") || !strings.HasSuffix(e.Name(), ".jsonl") {
				continue
			}
			info, err := e.Info()
			if err != nil {
				continue
			}
			files = append(files, fileInfo{filepath.Join(root, d, e.Name()), info.ModTime()})
		}
	}
	if len(files) == 0 {
		return nil, fmt.Errorf("rollout ファイルが見つからない: %s", root)
	}
	sort.Slice(files, func(i, j int) bool { return files[i].mtime.After(files[j].mtime) })
	paths := make([]string, len(files))
	for i, f := range files {
		paths[i] = f.path
	}
	return paths, nil
}

func sortedDirNames(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names) // "2026" や "08" はゼロ埋めなので文字列順 = 時系列順
	return names, nil
}

// lastRateLimits はファイル内の最後の rate_limits を読む。
// 行の外側の構造（event の種類や入れ子）は codex のバージョンで動くので、
// 「行のどこかに rate_limits オブジェクトがある」ことだけに依存する。
func lastRateLimits(path string) (*Window, bool) {
	f, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer f.Close()

	var lastLine string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024) // rollout の1行は長い
	for sc.Scan() {
		if strings.Contains(sc.Text(), `"rate_limits"`) {
			lastLine = sc.Text()
		}
	}
	if lastLine == "" {
		return nil, false
	}

	var raw map[string]any
	if err := json.Unmarshal([]byte(lastLine), &raw); err != nil {
		return nil, false
	}
	rl := findRateLimits(raw)
	if rl == nil {
		return nil, false
	}
	b, err := json.Marshal(rl)
	if err != nil {
		return nil, false
	}
	var parsed struct {
		Primary   *codexWindow `json:"primary"`
		Secondary *codexWindow `json:"secondary"`
	}
	if err := json.Unmarshal(b, &parsed); err != nil {
		return nil, false
	}
	w := pickWeekly(parsed.Primary, parsed.Secondary)
	if w == nil {
		return nil, false
	}
	return &Window{Percent: int(math.Round(w.UsedPercent)), ResetsAt: w.ResetsAt}, true
}

type codexWindow struct {
	UsedPercent   float64 `json:"used_percent"`
	WindowMinutes int     `json:"window_minutes"`
	ResetsAt      int64   `json:"resets_at"`
}

// pickWeekly は weekly 窓（>= 10080 分）を選ぶ。無ければ primary に倒す。
func pickWeekly(primary, secondary *codexWindow) *codexWindow {
	for _, w := range []*codexWindow{primary, secondary} {
		if w != nil && w.WindowMinutes >= weeklyWindowMinutes {
			return w
		}
	}
	return primary
}

// findRateLimits は入れ子の map から "rate_limits" キーを探す。
func findRateLimits(m map[string]any) map[string]any {
	if v, ok := m["rate_limits"].(map[string]any); ok {
		return v
	}
	for _, v := range m {
		if child, ok := v.(map[string]any); ok {
			if found := findRateLimits(child); found != nil {
				return found
			}
		}
	}
	return nil
}
