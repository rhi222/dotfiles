// Package worktree は消し忘れた git worktree の洗い出しと掃除を行う。
//
// **判定と観測を分けているのが Shell 版との一番の差。** Shell 版は
// classify_worktree の中で git を呼び、printf で表示まで済ませていたため、
// 分岐だけを検査できなかった（テストは実 git リポジトリを作るしかなかった）。
// ここでは git・filesystem・gh からの観測を Observation へ集めてから、
// 純粋関数 Classify で判定する。
package worktree

import "fmt"

// Verdict は worktree1つに対する判定。
type Verdict int

const (
	// KEEP は残す（消してよいと判断できなかった）。
	KEEP Verdict = iota
	// DELETE は worktree ディレクトリを消す。ローカルブランチは消さない。
	DELETE
	// SKIP は明示的に触らない（locked / detached / 作業中）。
	SKIP
	// PRUNE はディレクトリが既に無く、admin エントリの掃除が要る。
	PRUNE
)

func (v Verdict) String() string {
	switch v {
	case DELETE:
		return "DELETE"
	case SKIP:
		return "SKIP"
	case PRUNE:
		return "PRUNE"
	default:
		return "KEEP"
	}
}

// SkipKind は SKIP の内訳。サマリ行に件数を出すために持つ。
type SkipKind int

const (
	// SkipNone は SKIP でないことを表す。
	SkipNone SkipKind = iota
	// SkipLocked は locked による SKIP。
	SkipLocked
	// SkipDetached は detached HEAD による SKIP。
	SkipDetached
	// SkipDirty は追跡ファイルの未コミット変更による SKIP。
	SkipDirty
)

// PRKind は PR の状態。
type PRKind int

const (
	// PRUnavailable は取得できなかった（未認証・権限不足・ネットワーク断）。
	PRUnavailable PRKind = iota
	// PRNone は対応する PR が無い。
	PRNone
	// PROpen は未マージで開いている。
	PROpen
	// PRMerged はマージ済み。
	PRMerged
	// PRClosed はマージされずに閉じられた。
	PRClosed
)

// PRState は PR の状態と、表示に使う生の文字列（"MERGED #10737" など）。
type PRState struct {
	Kind PRKind
	Raw  string
}

// Observation は worktree1つについて外界から集めた事実。
// **ここに集めきることで判定を純粋関数にする。**
type Observation struct {
	Repo   string
	Path   string
	Branch string // detached のとき空

	Locked      bool
	LockDetail  string
	Prunable    bool
	PruneDetail string

	// HasTrackedChanges は追跡ファイルに未コミット変更があるか。
	// **未追跡ファイルは含めない。** dirty の実体が plans/ 等の使い捨て
	// スクラッチ1件であることが多く、含めると DELETE がほぼ全部止まる。
	HasTrackedChanges bool
	UntrackedCount    int

	PR PRState
}

// Options は判定を変える利用者の指定。
type Options struct {
	// Force は追跡ファイルに未コミット変更がある worktree も削除対象にする。
	// **locked と detached には効かない。**
	Force bool
}

// Decision は判定の結果。
type Decision struct {
	Verdict  Verdict
	Reason   string
	SkipKind SkipKind
}

const unsetDetail = "理由未設定"

// Classify は Observation を判定する。副作用は無い。
//
// **上から順に評価し、最初にマッチした時点で確定する。順序に意味がある。**
// locked を最優先にしないと、実行中の Claude セッションの作業ディレクトリを
// 消しうる（Claude Code の worktree はセッション実行中に lock される）。
func Classify(o Observation, opt Options) Decision {
	// 1. locked: Claude セッション実行中の可能性があるため必ず残す。
	//    --force でも解除しない（二重 force は実装しない）。
	if o.Locked {
		return Decision{SKIP, fmt.Sprintf("locked (%s)", detailOr(o.LockDetail)), SkipLocked}
	}

	// 2. prunable: ディレクトリが既に無い。削除ではなく prune の対象。
	if o.Prunable {
		return Decision{PRUNE, fmt.Sprintf("ディレクトリ消失 (%s)", detailOr(o.PruneDetail)), SkipNone}
	}

	// 3. detached HEAD: ブランチが無く PR 判定ができない。
	if o.Branch == "" {
		return Decision{SKIP, "detached HEAD（PR判定不能）", SkipDetached}
	}

	// 4. 追跡ファイルの未コミット変更: 作業中の可能性。--force で解除できる。
	if !opt.Force && o.HasTrackedChanges {
		return Decision{SKIP, "未コミット変更あり（--force で削除対象に含める）", SkipDirty}
	}

	// 5. PR が取れない: 判定不能なときは削除側へ倒さない。
	if o.PR.Kind == PRUnavailable {
		return Decision{KEEP, "PR状態の取得に失敗", SkipNone}
	}

	// 6. MERGED / CLOSED: 削除対象。
	if o.PR.Kind == PRMerged || o.PR.Kind == PRClosed {
		reason := o.PR.Raw
		// --force 時は追跡ファイルの未コミット変更が破棄される。何が失われるかを
		// 行に出す。FORCE=0 のときはルール4で SKIP 済みなのでここには来ない。
		if opt.Force && o.HasTrackedChanges {
			reason += "（未コミット変更あり・破棄されます）"
		}
		// 未追跡があれば件数を併記する（使い捨てスクラッチを黙って消さないため）。
		if o.UntrackedCount > 0 {
			reason += fmt.Sprintf("（未追跡 %d 件あり）", o.UntrackedCount)
		}
		return Decision{DELETE, reason, SkipNone}
	}

	// 7. PR なし。
	if o.PR.Kind == PRNone {
		return Decision{KEEP, "PR なし", SkipNone}
	}

	// 8. それ以外（OPEN など）は raw をそのまま理由にする。
	return Decision{KEEP, o.PR.Raw, SkipNone}
}

func detailOr(s string) string {
	if s == "" {
		return unsetDetail
	}
	return s
}
