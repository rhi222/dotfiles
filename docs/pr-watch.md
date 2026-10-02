# 自分のPRの夜間見張り

自分が作ったopenなPRを夜間に見張り、CI失敗と未対応のレビュー指摘をheadless Claudeで直す。
会話セッション内で1つのPRを回す `/pr-watch` skillの夜間版で、PRを指定しなくても全部を見る。

| 操作         | コマンド                                            |
| ------------ | --------------------------------------------------- |
| 判定だけ見る | `bash scripts/prwatch/nightly.sh --dry-run`         |
| 有効化       | `touch ~/.config/pr-watch-enabled`                  |
| 前回の結果   | `cat ~/.local/state/pr-watch/last-run.txt`          |
| 判断の全文   | `~/.local/state/pr-watch/<owner>_<repo>_<番号>.log` |

cronは火〜土の1:30（Linearの夜間dispatchの後）。

## なぜLinearを経由しないか

Linearの実装レーンは、issue本文の `repo:` 行を人が整形しないと動かず、1か月以上0件だった。
PRはURLからrepoもブランチも決まるので、人が足す情報が無い。
入口を「自分のopenなPR」にすれば、覚えることが無くなる。

## 対象の判定

`gh search prs --author @me --state open` のうち、次のどちらかに当たるものだけを直す。

| 理由       | 条件                                                                       |
| ---------- | -------------------------------------------------------------------------- |
| `ci`       | 最新コミットのCIが `FAILURE` / `ERROR`                                     |
| `feedback` | 未解決かつoutdatedでないレビュースレッドがある、または `CHANGES_REQUESTED` |

**botの指摘も人の指摘と同じく拾う。**
AIレビューbot（GitHub Actions）の指摘にも対応したいため。
妥当でない指摘はagentがコードを変えずに理由を残し、同じheadでは繰り返さない。

1晩に手を動かすのは最大3件（`PR_WATCH_MAX`）。

agentの出力は全文をPRごとに残し、結果行にその場所を出す。
指摘ごとの判断理由は出力の先頭に来ることが多く、末尾だけでは読めなかった。
CIが落ちていないPRには、CIの失敗ログ欄を渡さない。
空の欄を渡すと、agentが落ちていないCIを調べに行っていた。

## 安全弁

- **pushするのはdraft PRだけ。**
  レビュー中のPRは、修正コミットを `<repo>/.wt/pr-watch-<番号>` に残し、結果に「push待ち」とpushコマンドを出す。
  レビュアーの見ているPRへ無人でpushしないため
- **ローカルブランチは触らない。**
  worktreeはdetachedで作り、`HEAD:<branch>` へpushする。
  同名のローカルブランチに未pushの作業があっても壊さない
- **同じheadでは繰り返さない。**
  対応したheadのSHAを `~/.local/state/pr-watch/` に記録する。
  直せなかったときも記録し、新しいpushかレビューでheadが変わるまで再挑戦しない
- **agentに `gh` を渡さない。**
  CIの失敗ログとレビュー指摘はスクリプトが取得してプロンプトに入れる
- **GitHubへはpush以外を書き込まない。**
  コメント、スレッドのresolve、ラベルはしない（[linear-command-layer.md](linear-command-layer.md) の書き戻し禁止と同じ）

push待ちのworktreeを残している間、そのPRはスキップされる。
朝に中身を見てpushするか、捨てるなら `git worktree remove` する。
