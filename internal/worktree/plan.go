package worktree

// Item は worktree 1件の判定結果と、表示・削除に要る情報。
type Item struct {
	Path     string
	Branch   string
	SizeKB   int // --size のときだけ測る
	Decision Decision
}

// Label は表示に使うブランチ名。detached のとき括弧つきの既定文になる。
func (i Item) Label() string {
	if i.Branch == "" {
		return "（detached）"
	}
	return i.Branch
}

// RepoPlan は1リポジトリ分の判定結果。
type RepoPlan struct {
	Repo  string
	Items []Item
}

// HasPrunable はこのリポジトリに prune 対象があるか。
func (r RepoPlan) HasPrunable() bool {
	for _, it := range r.Items {
		if it.Decision.Verdict == PRUNE {
			return true
		}
	}
	return false
}

// Plan は「何をどうするか」の全体。
//
// **表示と実行が同じ Plan を読むのが要点。** Shell 版は process_repo が表示と
// 集計を同時に行い、削除は別に持った DELETE_PATHS 配列を回していたので、
// 「表示したものと消すもの」が構造的にずれうる形だった。
type Plan struct {
	Roots string
	Repos []RepoPlan

	// --size の集計
	FreedKB int

	// 実行後に埋まる
	Executed     bool
	Deleted      int
	DeleteFailed int
}

// Counts は分類ごとの件数。
type Counts struct {
	Delete       int
	Prune        int
	Skip         int
	Keep         int
	SkipLocked   int
	SkipDetached int
	SkipDirty    int
}

// Counts は Plan 全体を集計する。
func (p *Plan) Counts() Counts {
	var c Counts
	for _, rp := range p.Repos {
		for _, it := range rp.Items {
			switch it.Decision.Verdict {
			case DELETE:
				c.Delete++
			case PRUNE:
				c.Prune++
			case SKIP:
				c.Skip++
				switch it.Decision.SkipKind {
				case SkipLocked:
					c.SkipLocked++
				case SkipDetached:
					c.SkipDetached++
				default:
					c.SkipDirty++
				}
			default:
				c.Keep++
			}
		}
	}
	return c
}

// Deletions は削除対象を (repo, path) の組で返す。
func (p *Plan) Deletions() []Item2 {
	var out []Item2
	for _, rp := range p.Repos {
		for _, it := range rp.Items {
			if it.Decision.Verdict == DELETE {
				out = append(out, Item2{Repo: rp.Repo, Path: it.Path})
			}
		}
	}
	return out
}

// Item2 は削除対象のリポジトリとパスの組。
type Item2 struct {
	Repo string
	Path string
}

// PruneRepos は prune が要るリポジトリを返す。
func (p *Plan) PruneRepos() []string {
	var out []string
	for _, rp := range p.Repos {
		if rp.HasPrunable() {
			out = append(out, rp.Repo)
		}
	}
	return out
}
