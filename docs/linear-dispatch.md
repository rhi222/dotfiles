# LinearのAI夜間dispatch

[linear-command-layer.md](linear-command-layer.md) から分割した、AI夜間dispatch、worktree、push、PR作成の設計記録。

## 2つのレーン

`AI Queued` は2つのランナーが分担する。振り分けは本文とラベルで決まる。

|                       | 実装レーン                      | EMレーン                                     |
| --------------------- | ------------------------------- | -------------------------------------------- |
| 対象                  | `repo:` 行 または PR URL を持つ | `role:manager` かつ `repo:` 行もPR URLも無い |
| スクリプト            | `dispatch-cron.sh`              | `em-dispatch.sh`                             |
| ランナー              | headless Claude                 | `codex exec`                                 |
| 起動                  | 夜間cron                        | `/nippo-add` での承認直後                    |
| 同時実行              | 1本                             | 1本（`flock`）                               |
| 1回の起動での処理上限 | 3件（`LINEAR_DISPATCH_MAX`）    | 3件（`LINEAR_EM_DISPATCH_MAX`）              |
| 成果物                | draft PR                        | `01_Inbox/ai/` の叩き台 + 確認質問           |

どちらの条件にも当てはまらないもの（`repo:` もPR URLも無く `role:manager` も無い）だけが `Todo` へ差し戻される。

**`codex exec` は必ず `< /dev/null` を付ける。** 付けないと `Reading additional input from stdin...` でEOFを待ち続けて固まる。バックグラウンド起動では必ず踏む。

**vaultの指示ファイルは複数形の `AGENTS.md`。** Codexは `CLAUDE.md` を読まず、`AGENT.md`（単数）も読まない。

## 起動条件とWIP上限

**夜間ディスパッチは「My Review」が `LINEAR_WIP_LIMIT`（既定10）件以上だと止まる。**
生成速度＞判断速度は仕組みが破綻しているシグナルなので、朝の判断タイムで捌いてから再開する。

- **起動条件は state = `AI Queued` の1点。**
  **ラベルは見ない。** パイプライン上の位置はstateで表し、ラベルと二重に持たない。
  `ai:blocked-human` だけは「そもそも委譲できない」属性なのでstateと直交する
- dispatchは本文の内容で2モードに分かれる

| 本文              | モード | 動作                                                             |
| ----------------- | ------ | ---------------------------------------------------------------- |
| 既存PRのURLがある | 継続   | そのPRのブランチをcheckoutして続きを進める。**新規PRは作らない** |
| `repo:` 行のみ    | 新規   | `linear/<identifier>` ブランチを切って新規draft PRを作る         |

## 新規と継続のモード

**子issueのタイトルのprefixがモードに対応する。**
`draft仕上げ:` は既存draft PRを指すので継続、`実装:` はPRがまだ無いので新規。
新規ブランチ方式のままだと重複PRができていた。
継続モードはPRが `OPEN` でなければ実行しない。
`draft仕上げ:` は `linear-sweep.sh` の自動起票と `/linear-add` の手動起票の両方で使うが、**どちらもPRが実在するものにしか付けない**（付けるとタイトルからモードを判別できなくなる）

## Worktreeのライフサイクル

- worktreeは `<repo>/.wt/linear-<identifier>` に作られる。
  **成功時（push/PR完了後）は dispatch自身がworktreeを掃除する**（newモードはブランチも `git branch -D`。
  continueモードのブランチは既存PRのものなので残す）。
  pushでリモートに上がっているのでローカルに残す意味が薄い
- **失敗時（Todoへ差し戻す経路）はworktreeとブランチを調査用に意図的に残す。**
  newモードは着手前に前回の残骸を掃除する（残っていると `worktree add -b` がブランチ既存で失敗し、再実行が恒久的に BOUNCED になる）。
  残りきったものは `worktree-cleanup.sh` も拾う
- 成果物はdraft PRまで。
  マージは必ず人間

## PushとPR作成の責務

**push と PR作成はagentではなくスクリプトが行う。**
Claude Code は `git push` を許可リストで上書きできない（`--allowedTools` / settings.json の `permissions.allow` / `acceptEdits` / `dontAsk` のいずれでも拒否される。
`git ls-remote` のような読み取りは通る）。
headlessのagentに任せると必ずPR作成に到達しないため、役割を分ける。

| 担当       | 範囲                                                               |
| ---------- | ------------------------------------------------------------------ |
| agent      | 実装してworktree内でコミットするまで（`gh` を渡さない）            |
| スクリプト | `git push` と `gh pr create --draft`（素のbash。権限層を通らない） |

- **PR作成権限はagent実行前に確認する**（`gh repo view --json viewerPermission`）。
  無いまま走らせるとagentを丸ごと1回動かした末に最後だけ失敗する。
  判定不能な場合も実行しない
- `gh` は業務アカウントで認証されている。
  **個人リポジトリ（`rhi222/*`）は `READ` しか無いのでdispatchできない**（業務orgのリポジトリは `ADMIN`）
- コミットが0件ならpushもPR作成もしない（実装に到達しなかったとみなす）
