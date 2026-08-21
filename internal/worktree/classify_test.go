package worktree

import "testing"

// 判定の仕様表。docs/worktree.md の表を機械検査できる形に落としたもの。
//
// **上から順に評価し、最初にマッチした時点で確定する。順序に意味がある。**
// locked を最優先にしないと、実行中の Claude セッションの作業ディレクトリを消しうる。
//
//  1. locked                          -> SKIP
//  2. prunable（ディレクトリ消失）     -> PRUNE
//  3. detached HEAD                   -> SKIP
//  4. 追跡ファイルに未コミット変更あり -> SKIP（--force で解除）
//  5. PR 取得失敗                     -> KEEP
//  6. PR が MERGED / CLOSED           -> DELETE
//  7. PR なし                         -> KEEP
//  8. それ以外（OPEN など）           -> KEEP
func TestClassify(t *testing.T) {
	tests := []struct {
		name        string
		obs         Observation
		force       bool
		wantVerdict Verdict
		wantReason  string
	}{
		// --- ルール1: locked ---
		{
			name:        "locked は理由つきで SKIP",
			obs:         Observation{Branch: "feat", Locked: true, LockDetail: "claude session"},
			wantVerdict: SKIP,
			wantReason:  "locked (claude session)",
		},
		{
			name:        "locked で理由が無ければ既定文を出す",
			obs:         Observation{Branch: "feat", Locked: true},
			wantVerdict: SKIP,
			wantReason:  "locked (理由未設定)",
		},
		{
			// **--force でも locked は消さない。** 二重 force は実装しない
			name:        "locked は --force でも SKIP",
			obs:         Observation{Branch: "feat", Locked: true, LockDetail: "in use"},
			force:       true,
			wantVerdict: SKIP,
			wantReason:  "locked (in use)",
		},
		{
			// locked が他の全条件より先に効くこと（順序の検査）
			name: "locked は prunable や PR より先に効く",
			obs: Observation{
				Branch: "feat", Locked: true, LockDetail: "x", Prunable: true,
				PR: PRState{Kind: PRMerged, Raw: "MERGED #1"},
			},
			wantVerdict: SKIP,
			wantReason:  "locked (x)",
		},

		// --- ルール2: prunable ---
		{
			name:        "prunable は PRUNE",
			obs:         Observation{Branch: "feat", Prunable: true, PruneDetail: "gitdir file points to non-existent location"},
			wantVerdict: PRUNE,
			wantReason:  "ディレクトリ消失 (gitdir file points to non-existent location)",
		},
		{
			name:        "prunable で理由が無ければ既定文を出す",
			obs:         Observation{Branch: "feat", Prunable: true},
			wantVerdict: PRUNE,
			wantReason:  "ディレクトリ消失 (理由未設定)",
		},
		{
			name: "prunable は detached や PR より先に効く",
			obs: Observation{
				Branch: "", Prunable: true, PruneDetail: "y",
				PR: PRState{Kind: PRMerged, Raw: "MERGED #1"},
			},
			wantVerdict: PRUNE,
			wantReason:  "ディレクトリ消失 (y)",
		},

		// --- ルール3: detached HEAD ---
		{
			name:        "detached HEAD は PR 判定できないので SKIP",
			obs:         Observation{Branch: ""},
			wantVerdict: SKIP,
			wantReason:  "detached HEAD（PR判定不能）",
		},
		{
			name:        "detached は --force でも SKIP",
			obs:         Observation{Branch: ""},
			force:       true,
			wantVerdict: SKIP,
			wantReason:  "detached HEAD（PR判定不能）",
		},

		// --- ルール4: 追跡ファイルの未コミット変更 ---
		{
			name:        "追跡変更があれば SKIP",
			obs:         Observation{Branch: "feat", HasTrackedChanges: true, PR: PRState{Kind: PRMerged, Raw: "MERGED #1"}},
			wantVerdict: SKIP,
			wantReason:  "未コミット変更あり（--force で削除対象に含める）",
		},
		{
			// **未追跡だけなら止めない。** dirty の実体が plans/ 等の使い捨て1件で
			// あることが多く、未追跡を dirty に含めると DELETE がほぼ全部止まる
			name:        "未追跡だけなら SKIP しない",
			obs:         Observation{Branch: "feat", UntrackedCount: 3, PR: PRState{Kind: PRMerged, Raw: "MERGED #1"}},
			wantVerdict: DELETE,
			wantReason:  "MERGED #1（未追跡 3 件あり）",
		},

		// --- ルール5: PR 取得失敗 ---
		{
			// 判定不能なときは削除側へ倒さない
			name:        "PR が取れなければ KEEP",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PRUnavailable}},
			wantVerdict: KEEP,
			wantReason:  "PR状態の取得に失敗",
		},
		{
			name:        "PR が取れなければ --force でも KEEP",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PRUnavailable}},
			force:       true,
			wantVerdict: KEEP,
			wantReason:  "PR状態の取得に失敗",
		},

		// --- ルール6: MERGED / CLOSED ---
		{
			name:        "MERGED は DELETE",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PRMerged, Raw: "MERGED #10737"}},
			wantVerdict: DELETE,
			wantReason:  "MERGED #10737",
		},
		{
			name:        "CLOSED も DELETE",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PRClosed, Raw: "CLOSED #99"}},
			wantVerdict: DELETE,
			wantReason:  "CLOSED #99",
		},
		{
			// --force のときだけ到達する（FORCE=0 ならルール4で SKIP 済み）。
			// 何が失われるかを行に出す
			name:        "--force で追跡変更ありなら破棄を明示する",
			obs:         Observation{Branch: "feat", HasTrackedChanges: true, PR: PRState{Kind: PRMerged, Raw: "MERGED #1"}},
			force:       true,
			wantVerdict: DELETE,
			wantReason:  "MERGED #1（未コミット変更あり・破棄されます）",
		},
		{
			name: "--force で追跡変更と未追跡が両方あれば両方併記する",
			obs: Observation{
				Branch: "feat", HasTrackedChanges: true, UntrackedCount: 2,
				PR: PRState{Kind: PRMerged, Raw: "MERGED #1"},
			},
			force:       true,
			wantVerdict: DELETE,
			wantReason:  "MERGED #1（未コミット変更あり・破棄されます）（未追跡 2 件あり）",
		},

		// --- ルール7-8: KEEP ---
		{
			name:        "PR が無ければ KEEP",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PRNone}},
			wantVerdict: KEEP,
			wantReason:  "PR なし",
		},
		{
			name:        "OPEN は raw をそのまま理由にする",
			obs:         Observation{Branch: "feat", PR: PRState{Kind: PROpen, Raw: "OPEN #11068"}},
			wantVerdict: KEEP,
			wantReason:  "OPEN #11068",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Classify(tt.obs, Options{Force: tt.force})
			if got.Verdict != tt.wantVerdict {
				t.Errorf("Verdict = %v, want %v", got.Verdict, tt.wantVerdict)
			}
			if got.Reason != tt.wantReason {
				t.Errorf("Reason:\n got  %q\n want %q", got.Reason, tt.wantReason)
			}
		})
	}
}

// SKIP の内訳はサマリ行に出るので、分類だけでなく理由の種別も要る。
func TestSkipKindForSummary(t *testing.T) {
	tests := []struct {
		name string
		obs  Observation
		want SkipKind
	}{
		{"locked", Observation{Branch: "b", Locked: true}, SkipLocked},
		{"detached", Observation{Branch: ""}, SkipDetached},
		{"dirty", Observation{Branch: "b", HasTrackedChanges: true}, SkipDirty},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Classify(tt.obs, Options{})
			if got.Verdict != SKIP {
				t.Fatalf("Verdict = %v, want SKIP", got.Verdict)
			}
			if got.SkipKind != tt.want {
				t.Errorf("SkipKind = %v, want %v", got.SkipKind, tt.want)
			}
		})
	}
}
