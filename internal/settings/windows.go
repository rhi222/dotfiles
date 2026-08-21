package settings

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/rhi222/dotfiles/internal/execx"
)

// WindowsTarget は Windows 側設定の同期対象。
type WindowsTarget struct {
	Name string
	Live string
	Repo string
	// JSON なら jq -S 相当で正規化する。
	//
	// **`.wslconfig` は INI なので素通しする。** JSON バリデータに掛けると
	// 通らないうえ、値の導出過程を書いたコメントが消える。
	JSON bool
	// Note は反映に必要な操作の案内。
	Note string
}

// WindowsTargets は既定の対象一覧。**順序は表示順**（wslconfig -> terminal）。
func WindowsTargets(cfg WindowsConfig) []WindowsTarget {
	return []WindowsTarget{
		{
			Name: "wslconfig",
			Live: cfg.WSLConfigLive,
			Repo: cfg.WSLConfigRepo,
			JSON: false,
			Note: "反映には `wsl --shutdown` が必要です。",
		},
		{
			Name: "terminal",
			Live: cfg.TerminalLive,
			Repo: cfg.TerminalRepo,
			JSON: true,
			Note: "反映には Windows Terminal の再起動が必要です。",
		},
	}
}

// WindowsConfig は Windows 側設定の同期に要るパス。
type WindowsConfig struct {
	WSLConfigLive string
	WSLConfigRepo string
	TerminalLive  string
	TerminalRepo  string
}

// FindTerminalSettings は Store 版 Windows Terminal の settings.json を探す。
//
// **パッケージ名は固定だがハッシュ部が変わりうるので glob で拾う。**
// Preview 版は別パッケージ名なので巻き込まない。
func FindTerminalSettings(winUser string) string {
	pattern := filepath.Join("/mnt/c/Users", winUser,
		"AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return ""
	}
	for _, d := range matches {
		if st, serr := os.Stat(d); serr == nil && st.IsDir() {
			return filepath.Join(d, "settings.json")
		}
	}
	return ""
}

// WinUser は Windows 側のユーザー名を取る。
func WinUser(ctx context.Context, r execx.Runner) string {
	res, err := r.Run(ctx, execx.Cmd{Name: "cmd.exe", Args: []string{"/c", "echo", "%USERNAME%"}})
	if err != nil || !res.OK() {
		return ""
	}
	return strings.TrimRight(res.Stdout, "\r\n")
}

// readTarget は対象を読んで（JSON なら正規化して）返す。
func readTarget(t WindowsTarget, path, label string, w IO) (string, bool) {
	if path == "" {
		fmt.Fprintf(w.err(), "ERROR: %s のパスを解決できません（%s）\n", label, t.Name)
		return "", false
	}
	b, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: %s が見つかりません: %s\n", label, path)
		return "", false
	}
	if !t.JSON {
		return string(b), true
	}
	c, cerr := Canonical(b)
	if cerr != nil {
		fmt.Fprintf(w.err(), "ERROR: %s が正しいJSONではありません: %s\n", label, path)
		return "", false
	}
	return c, true
}

// WindowsPull は実ファイルをリポジトリへ取り込む。
func WindowsPull(ctx context.Context, r execx.Runner, t WindowsTarget, dryRun bool, w IO) Outcome {
	content, ok := readTarget(t, t.Live, "実ファイル", w)
	if !ok {
		return Failed
	}
	return Pull(ctx, r, content, t.Repo, dryRun, Messages{
		Unchanged: fmt.Sprintf("変更なし [%s]: リポジトリは実ファイルと一致しています", t.Name),
		DryRun:    fmt.Sprintf("更新あり [%s]（--dry-run のため書き込みません）: %s", t.Name, t.Repo),
		Updated:   fmt.Sprintf("更新 [%s]: %s に実ファイルの内容を取り込みました", t.Name, t.Repo),
	}, w)
}

// WindowsPush はリポジトリの内容を実ファイルへ書き出す。
func WindowsPush(ctx context.Context, r execx.Runner, t WindowsTarget, force bool, w IO) Outcome {
	content, ok := readTarget(t, t.Repo, "リポジトリ版", w)
	if !ok {
		return Failed
	}
	if t.Live == "" {
		fmt.Fprintf(w.err(), "ERROR: 実ファイルのパスを解決できません（%s）\n", t.Name)
		return Failed
	}

	if _, err := os.Stat(t.Live); err != nil {
		return CreateMissing(content, t.Live, Messages{
			Created: fmt.Sprintf("作成 [%s]: %s をリポジトリ版から作成しました。%s", t.Name, t.Live, t.Note),
		}, w)
	}

	liveContent, ok := readTarget(t, t.Live, "実ファイル", w)
	if !ok {
		// **壊れている場合は --force でのみ復旧させる。**
		if !force {
			return Failed
		}
		if _, err := WriteIfChanged(content, t.Live); err != nil {
			fmt.Fprintf(w.err(), "ERROR: 書き込みに失敗: %v\n", err)
			return Failed
		}
		fmt.Fprintf(w.out(), "上書き [%s]: 壊れた %s をリポジトリ版で復旧しました。%s\n", t.Name, t.Live, t.Note)
		return Restored
	}

	reject := fmt.Sprintf(`ERROR: 実ファイルとリポジトリに差分があるため push しません（%s）。
  実ファイル: %s
  リポジトリ: %s

実ファイル側の変更を残すなら pull を、
リポジトリ側で上書きしてよいなら push --force を実行してください。
差分（左: リポジトリ / 右: 実ファイル）:`, t.Name, t.Live, t.Repo)

	return Push(ctx, r, content, liveContent, content, t.Live, force, Messages{
		Unchanged:    fmt.Sprintf("変更なし [%s]: 実ファイルはリポジトリと一致しています", t.Name),
		Overwritten:  fmt.Sprintf("上書き [%s]: %s をリポジトリ版で上書きしました。%s", t.Name, t.Live, t.Note),
		RejectHeader: reject,
	}, w)
}

// WindowsStatus は差分の有無だけを報告する。
func WindowsStatus(ctx context.Context, r execx.Runner, t WindowsTarget, w IO) Outcome {
	liveContent, ok := readTarget(t, t.Live, "実ファイル", w)
	if !ok {
		return Failed
	}
	repoContent, ok := readTarget(t, t.Repo, "リポジトリ版", w)
	if !ok {
		return Failed
	}
	return Status(ctx, r, repoContent, liveContent, Messages{
		Unchanged: fmt.Sprintf("一致 [%s]: 実ファイルとリポジトリは同じ内容です", t.Name),
		DryRun:    fmt.Sprintf("差分あり [%s]（左: リポジトリ / 右: 実ファイル）", t.Name),
	}, w)
}
