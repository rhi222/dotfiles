# git worktree の運用

`git wt` で作った worktree の初期化・一覧表示・掃除。

## worktree初期化のリポジトリ別カスタム

`git wt` でworktreeを作成すると `scripts/worktree-init.sh` が走り、共通処理（gitignore対象の
`.env*` コピー・lockファイル判定による依存インストール）を行う。共通処理の後に、リポジトリ固有の
追加初期化を差し込める。

- 置き場所: `scripts/worktree-init.d/<host>/<owner>/<repo>.sh`
  （例 `scripts/worktree-init.d/github.com/rhi222/dotfiles.sh`）
- キーは `git remote get-url origin` の正規化名（`git@`/`https`/`ssh` いずれの形式でも同一キーに解決）
- 固有スクリプトは `cwd=worktreeパス`・第1引数にworktreeパスが渡って実行される
- 固有スクリプトが失敗しても警告が出るだけで worktree 作成フローは継続する（`worktree-init.sh` は exit 0）
- 該当スクリプトが無いリポジトリ、または origin未設定のリポジトリでは共通処理のみ実行される

## worktree 一覧のタグ表示（wt / wtd）

`wt` / `wtd` の fzf 一覧の1列目に、その worktree の由来をタグで出す。整形は
`__wt_format_rows`、メインworktreeの解決は `__wt_main_path` に分離している。

| タグ     | 意味                                         |
| -------- | -------------------------------------------- |
| `main`   | メインworktree（本体）                       |
| `.wt`    | `git wt` が作る `.wt/` 配下                  |
| `claude` | Claude Code が作る `.claude/worktrees/` 配下 |
| `wt`     | それ以外の場所にあるリンクworktree           |

**メイン判定は `git worktree list --porcelain` の先頭エントリとの実パス一致で行う。**
以前はパスに `.wt` を含むかだけで見ていたため、`.claude/worktrees/` 配下の worktree が
`[main]` と表示されていた（`.claude` に `.wt` は含まれないため）。逆にメインworktreeの
パスに `.wt` が含まれると `[.wt]` になる誤判定もあった。置き場所が増えても壊れないよう、
「メインかどうか」だけを git に聞き、由来の細分はパスの位置で行う。

タグのパディングは**括弧の外側**に入れる（`[main]  `）。`[main  ]` のように内側へ入れると
`wt` / `wtd` が `awk` で拾うフィールド番号がずれる。

動作確認は `bash scripts/test-wt-select.sh`。

## worktree の掃除

消し忘れた worktree を洗い出して削除する。**既定は dry-run** で、実削除には `--execute` が必要。

| やりたいこと               | コマンド                                             |
| -------------------------- | ---------------------------------------------------- |
| 候補の確認（dry-run）      | `bash scripts/worktree-cleanup.sh`                   |
| 解放見込みつきで確認       | `bash scripts/worktree-cleanup.sh --size`            |
| 実削除                     | `bash scripts/worktree-cleanup.sh --execute`         |
| 追跡ファイルの変更ごと削除 | `bash scripts/worktree-cleanup.sh --execute --force` |
| 動作確認                   | `bash scripts/test-worktree-cleanup.sh`              |

`git worktree list --porcelain` を起点にするため、worktree の置き場所を問わず拾える。
`.wt/`（`git wt`）・`.claude/worktrees/`（Claude Code）・`/tmp`・旧 `~/git-worktrees/` が
実際に混在していたが、いずれも走査対象になる。走査ルートの既定は `/data/git-repos`
（`WORKTREE_CLEANUP_ROOTS` で変更可能）。

判定は上から順に評価し、最初にマッチした時点で確定する。

| 順  | 条件                                  | 判定       |
| --- | ------------------------------------- | ---------- |
| 1   | `locked`                              | **SKIP**   |
| 2   | `prunable`（ディレクトリ消失）        | **PRUNE**  |
| 3   | detached HEAD                         | **SKIP**   |
| 4   | 追跡ファイルに未コミット変更あり      | **SKIP**   |
| 5   | PR が MERGED または CLOSED            | **DELETE** |
| 6   | それ以外（OPEN / PRなし / `gh` 失敗） | **KEEP**   |

**`locked` を最優先にしているのが安全性の要。** Claude Code の worktree はセッション実行中に
lock されるため、これを PR 状態より先に判定しないと作業中のディレクトリを消す。`--force` は
ルール4だけを飛ばし、**`locked` は `--force` でも削除しない**（`git worktree remove -f -f` は
実装していない）。`gh` の呼び出しに失敗した場合も KEEP に倒すので、判定不能なときに削除側へ
行くことはない。

**未追跡ファイルは dirty 扱いにしない。** `plans/`（superpowers のスクラッチ）や
レビューメモのような使い捨てファイル1個で、マージ済み worktree の削除がほぼ全部
ブロックされてしまうため（実測で削除候補が6件から1件に落ちた）。ただし黙って消さないよう、
DELETE 行に `（未追跡 N 件あり）` と件数を併記する。N は**未追跡エントリ数**で、
未追跡ディレクトリは配下のファイル数ではなく1件として数える。

**ローカルブランチは削除しない。** そのため CLOSED を削除してもコミット済みの作業はブランチに
残り、消えるのは worktree ディレクトリと `node_modules` 等の再生成可能なファイルだけになる。

`--force` を使うと追跡ファイルの未コミット変更は失われる。その場合 dry-run の DELETE 行に
`（未コミット変更あり・破棄されます）` が併記されるので、実行前に一覧を目視すること。

削除は常に `git worktree remove --force` で行う。git は**未追跡ファイルがあるだけでも
`--force` なしの削除を拒否する**ため、これを付けないと未追跡のみの worktree（＝実際の
削除候補の大半）が消せない。安全性はスクリプトの `--force` フラグではなく上の判定表が
担保している。DELETE に到達するのは locked でも prunable でも detached でもなく、
追跡ファイルがクリーンか利用者が明示的に `--force` を指定したものだけ。
`git worktree remove -f -f`（二重 force）は実装していないので、`locked` は
`--force` を付けても削除されない。

削除に失敗した場合は git のエラーメッセージをそのまま表示する。`git worktree remove` は
**ディレクトリ削除に失敗しても管理エントリだけは消す**ため、孤児ディレクトリが残ることが
ある。そうなると以降 `git worktree list` に出てこず、このスクリプトでは検出できない。
エラーが出たらそのパスを手で確認すること。

**サマリの件数は dry-run と `--execute` で意味が違うので文言を分けている。** dry-run は
`DELETE 候補: N 件`（分類結果）、`--execute` は `削除: N 件`（実際に消せた件数）で、
失敗が1件以上あるときだけ `削除失敗: M 件` を足す。`--execute` でも「候補」と出していた頃は、
3件消した直後のサマリが `DELETE 候補: 3 件` になり「まだ候補が残っている」と読めた。加えて
この件数は分類時のカウンタなので、削除に失敗しても減らず成功したように見えていた。
機械可読行の `DELETE_CANDIDATES=N` は**常に分類結果**のまま（`daily-update.sh` は dry-run で
しか読まないので意味を変えない）で、`--execute` のときだけ後ろに `DELETED=n DELETE_FAILED=m`
を足す。

`--size` を既定にしないのは `du -sh` が重いため（793MB の worktree で数十秒かかった）。
測定対象も DELETE 候補だけに絞っている。

`daily-update.sh` が毎日 dry-run で候補を数え、**5件以上**で Windowsトースト通知を出す
（閾値は `WORKTREE_CLEANUP_NOTIFY_THRESHOLD`）。このステップは情報提供なので `run_step_soft`
で実行し、`gh` 未認証などで失敗しても daily-update 全体を FAILED にしない。件数は表示行では
なく機械可読なサマリ行 `worktree-cleanup: DELETE_CANDIDATES=N ...` から取る。この行は
dry-run では最終行にならない（後ろに案内が出る）ため `grep '^worktree-cleanup:'` で
行頭アンカーして拾う。

WSL2 のディスクイメージは中で削除しても自動では縮まない。実ディスクの空きを取り戻すには
`bash scripts/wsl-cleanup.sh` の末尾に出る `ext4.vhdx` 圧縮手順を Windows 側で実行する。

---

この文書は [AGENTS.md](../AGENTS.md) から切り出したもの。AGENTS.md 側には要点と入口だけを残してある。
