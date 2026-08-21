package settings

import (
	"context"
	"fmt"
	"os"

	"github.com/rhi222/dotfiles/internal/execx"
)

// ClaudeConfig は ~/.claude/settings.json 同期の設定。
type ClaudeConfig struct {
	// Live は実ファイル（~/.claude/settings.json）。
	Live string
	// Repo はリポジトリ側（.config/claude/settings.json）。
	Repo string
	// SecretDict は機密語辞書（~/.config/dotfiles/secret-patterns.txt）。
	SecretDict string
}

// readCanonicalJSON はファイルを読んで正規化する。
// **壊れた設定を相手側へ伝播させないための門番。**
func readCanonicalJSON(path, label string, w IO) (string, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: %s が見つかりません: %s\n", label, path)
		return "", false
	}
	c, err := Canonical(b)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: %s が正しいJSONではありません: %s\n", label, path)
		return "", false
	}
	return c, true
}

// ClaudePull は実ファイルをリポジトリへ取り込む（通常運用）。
func ClaudePull(ctx context.Context, r execx.Runner, cfg ClaudeConfig, dryRun bool, w IO) Outcome {
	content, ok := readCanonicalJSON(cfg.Live, "実ファイル", w)
	if !ok {
		return Failed
	}
	re, err := SecretRegex(cfg.SecretDict)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: 機密語辞書が読めません: %v\n", err)
		return Failed
	}
	// 社内固有のプラグイン設定はリポジトリに入れない（public のため）
	masked, err := Mask(content, re)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: マスクに失敗: %v\n", err)
		return Failed
	}

	return Pull(ctx, r, masked, cfg.Repo, dryRun, Messages{
		Unchanged: "変更なし: リポジトリは実ファイルと一致しています",
		DryRun:    fmt.Sprintf("更新あり（--dry-run のため書き込みません）: %s", cfg.Repo),
		Updated:   fmt.Sprintf("更新: %s に実ファイルの内容を取り込みました", cfg.Repo),
	}, w)
}

// ClaudePush はリポジトリの内容を実ファイルへ書き出す（新環境の bootstrap 用）。
func ClaudePush(ctx context.Context, r execx.Runner, cfg ClaudeConfig, force bool, w IO) Outcome {
	repoContent, ok := readCanonicalJSON(cfg.Repo, "リポジトリ版", w)
	if !ok {
		return Failed
	}

	if _, err := os.Stat(cfg.Live); err != nil {
		return CreateMissing(repoContent, cfg.Live, Messages{
			Created: fmt.Sprintf("作成: %s をリポジトリ版から作成しました", cfg.Live),
		}, w)
	}

	// **壊れている場合は --force でのみ復旧させる。** 黙って上書きすると
	// 「壊れていたこと」に気付けない。読めなかった事実は --force でも伝える。
	liveContent, liveOK := readCanonicalJSON(cfg.Live, "実ファイル", w)
	if !liveOK {
		if !force {
			return Failed
		}
		if _, err := WriteIfChanged(repoContent, cfg.Live); err != nil {
			fmt.Fprintf(w.err(), "ERROR: 書き込みに失敗: %v\n", err)
			return Failed
		}
		fmt.Fprintf(w.out(), "上書き: 壊れた %s をリポジトリ版で復旧しました\n", cfg.Live)
		return Restored
	}

	re, err := SecretRegex(cfg.SecretDict)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: 機密語辞書が読めません: %v\n", err)
		return Failed
	}

	// **比較はマスク後どうしで行う。** 実ファイル側の機密エントリはリポジトリに
	// 存在しないので、そうしないと機密の有無だけで常に「差分あり」になり、
	// push が拒否され続ける。
	liveMasked, err := Mask(liveContent, re)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: マスクに失敗: %v\n", err)
		return Failed
	}
	// 実ファイル側にしかない社内設定を消さないよう、書き戻す前にマージする
	merged, err := Merge(repoContent, liveContent, re)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: マージに失敗: %v\n", err)
		return Failed
	}

	reject := fmt.Sprintf(`ERROR: 実ファイルとリポジトリに差分があるため push しません。
  実ファイル: %s
  リポジトリ: %s

実ファイル側の変更（/config での操作など）を残すなら pull を、
リポジトリ側で上書きしてよいなら push --force を実行してください。
差分:`, cfg.Live, cfg.Repo)

	return Push(ctx, r, repoContent, liveMasked, merged, cfg.Live, force, Messages{
		Unchanged:    "変更なし: 実ファイルはリポジトリと一致しています",
		Overwritten:  fmt.Sprintf("上書き: %s をリポジトリ版で上書きしました（社内設定は保持）", cfg.Live),
		RejectHeader: reject,
	}, w)
}

// ClaudeStatus は差分の有無だけを報告する。
func ClaudeStatus(ctx context.Context, r execx.Runner, cfg ClaudeConfig, w IO) Outcome {
	liveContent, ok := readCanonicalJSON(cfg.Live, "実ファイル", w)
	if !ok {
		return Failed
	}
	repoContent, ok := readCanonicalJSON(cfg.Repo, "リポジトリ版", w)
	if !ok {
		return Failed
	}
	re, err := SecretRegex(cfg.SecretDict)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: 機密語辞書が読めません: %v\n", err)
		return Failed
	}
	// push と同じく、機密エントリの有無は差分として扱わない
	liveMasked, err := Mask(liveContent, re)
	if err != nil {
		fmt.Fprintf(w.err(), "ERROR: マスクに失敗: %v\n", err)
		return Failed
	}

	return Status(ctx, r, repoContent, liveMasked, Messages{
		Unchanged: "一致: 実ファイルとリポジトリは同じ内容です",
		DryRun:    "差分あり（左: リポジトリ / 右: 実ファイル）",
	}, w)
}
