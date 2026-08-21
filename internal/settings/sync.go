package settings

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/rhi222/dotfiles/internal/execx"
)

// Outcome は同期1回の結果。**表示と終了コードはこれだけで決まる。**
type Outcome int

const (
	// Unchanged は差分が無かった。
	Unchanged Outcome = iota
	// Written は書き込んだ。
	Written
	// WouldWrite は dry-run なので書かなかった。
	WouldWrite
	// Created は相手側が無かったので作った。
	Created
	// Rejected は差分があり --force が無いので書かなかった。
	Rejected
	// Restored は壊れていた相手を --force で復旧した。
	Restored
	// Failed は読めない・書けないなどで失敗した。
	Failed
)

// ExitCode は Outcome に対応する終了コード。
// **Rejected と Failed だけが非0**（安全弁が働いた、または壊れている）。
func (o Outcome) ExitCode() int {
	switch o {
	case Rejected, Failed:
		return 1
	default:
		return 0
	}
}

// WriteIfChanged は content を dest に書く。既に同一なら書かない。
//
// **同ディレクトリの一時ファイル + rename でアトミックに置き換える。** 途中で
// 中断されても書きかけの settings.json が残らないようにするため。既存ファイルの
// パーミッションは引き継ぐ（~/.claude/settings.json の 600 を崩さない）。
func WriteIfChanged(content, dest string) (changed bool, err error) {
	if cur, rerr := os.ReadFile(dest); rerr == nil && string(cur) == content {
		return false, nil
	}

	dir := filepath.Dir(dest)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}

	// 既存の権限を引き継ぐ。無ければ 0644（リダイレクトでの見え方に合わせる）
	mode := os.FileMode(0o644)
	if st, serr := os.Stat(dest); serr == nil {
		mode = st.Mode().Perm()
	}

	tmp, err := os.CreateTemp(dir, ".settings-sync.*")
	if err != nil {
		return false, err
	}
	tmpName := tmp.Name()
	defer func() {
		if err != nil {
			_ = os.Remove(tmpName)
		}
	}()

	if _, err = tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return false, err
	}
	if err = tmp.Close(); err != nil {
		return false, err
	}
	// CreateTemp は 600 で作るので、狙った権限へ直す
	if err = os.Chmod(tmpName, mode); err != nil {
		return false, err
	}
	if err = os.Rename(tmpName, dest); err != nil {
		return false, err
	}
	return true, nil
}

// Diff は2つの内容の差分を `diff` コマンドと同じ体裁で返す。
//
// **`diff` を呼ぶのは出力を変えないため。** 利用者が読むのはこの差分なので、
// 独自実装で体裁が変わると「同期の結果が読めない」になる。差分は表示専用で、
// 判定には使わない（判定は文字列の一致で行う）。
func Diff(ctx context.Context, r execx.Runner, left, right string) string {
	dir, err := os.MkdirTemp("", "settings-diff.")
	if err != nil {
		return ""
	}
	defer func() { _ = os.RemoveAll(dir) }()

	lp := filepath.Join(dir, "left")
	rp := filepath.Join(dir, "right")
	if os.WriteFile(lp, []byte(left), 0o600) != nil || os.WriteFile(rp, []byte(right), 0o600) != nil {
		return ""
	}
	res, err := r.Run(ctx, execx.Cmd{Name: "diff", Args: []string{lp, rp}})
	if err != nil {
		return ""
	}
	return res.Stdout
}

// Messages は1回の同期で使う文言。**呼び出し側が組み立てて渡す**ので、
// `[target]` の前置のような対象ごとの差をここで分岐しない。
type Messages struct {
	Unchanged    string
	DryRun       string
	Updated      string
	Created      string
	Overwritten  string
	Restored     string
	RejectHeader string
}

// IO は出力先。
type IO struct {
	Stdout io.Writer
	Stderr io.Writer
}

func (w IO) out() io.Writer {
	if w.Stdout == nil {
		return io.Discard
	}
	return w.Stdout
}

func (w IO) err() io.Writer {
	if w.Stderr == nil {
		return io.Discard
	}
	return w.Stderr
}

// Pull は content を dest へ反映する（実ファイル -> リポジトリ）。
func Pull(ctx context.Context, r execx.Runner, content, dest string, dryRun bool, m Messages, w IO) Outcome {
	cur, err := os.ReadFile(dest)
	if err == nil && string(cur) == content {
		fmt.Fprintln(w.out(), m.Unchanged)
		return Unchanged
	}

	if dryRun {
		fmt.Fprintln(w.out(), m.DryRun)
		if err == nil {
			fmt.Fprint(w.out(), Diff(ctx, r, string(cur), content))
		}
		return WouldWrite
	}

	if _, werr := WriteIfChanged(content, dest); werr != nil {
		fmt.Fprintf(w.err(), "ERROR: 書き込みに失敗: %s: %v\n", dest, werr)
		return Failed
	}
	fmt.Fprintln(w.out(), m.Updated)
	return Written
}

// Push は repoContent を dest へ書き出す（リポジトリ -> 実ファイル）。
//
//	liveCompare  比較に使う実ファイル側の内容（claude はマスク後）
//	writeContent 実際に書き出す内容（claude は機密マージ後）
//
// **--force なしで差分があれば書き込まない。** これが安全弁で、実ファイル側の
// 変更（/config での操作など）を黙って捨てないための門。
func Push(ctx context.Context, r execx.Runner, repoContent, liveCompare, writeContent, dest string, force bool, m Messages, w IO) Outcome {
	if repoContent == liveCompare {
		fmt.Fprintln(w.out(), m.Unchanged)
		return Unchanged
	}

	if !force {
		fmt.Fprintln(w.err(), m.RejectHeader)
		fmt.Fprint(w.err(), Diff(ctx, r, repoContent, liveCompare))
		return Rejected
	}

	if _, werr := WriteIfChanged(writeContent, dest); werr != nil {
		fmt.Fprintf(w.err(), "ERROR: 書き込みに失敗: %s: %v\n", dest, werr)
		return Failed
	}
	fmt.Fprintln(w.out(), m.Overwritten)
	return Written
}

// Status は差分の有無だけを報告する（何も書き換えない）。
func Status(ctx context.Context, r execx.Runner, repoContent, liveCompare string, m Messages, w IO) Outcome {
	if repoContent == liveCompare {
		fmt.Fprintln(w.out(), m.Unchanged)
		return Unchanged
	}
	fmt.Fprintln(w.out(), m.DryRun)
	fmt.Fprint(w.out(), Diff(ctx, r, repoContent, liveCompare))
	return WouldWrite
}

// CreateMissing は相手が無い場合に作る。
func CreateMissing(content, dest string, m Messages, w IO) Outcome {
	if _, err := WriteIfChanged(content, dest); err != nil {
		fmt.Fprintf(w.err(), "ERROR: 作成に失敗: %s: %v\n", dest, err)
		return Failed
	}
	fmt.Fprintln(w.out(), m.Created)
	return Created
}
