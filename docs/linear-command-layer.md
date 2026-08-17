# Linear個人司令塔（タスク集約とAI夜間ディスパッチ）

タスクはLinear（https://linear.app/nsym・team `NSY`）に集約する。**LinearはSoTではなく
「ポインタの司令塔」**で、issueは元URL＋期待アウトカム＋判断状態だけを持つ。本体はJira /
GitHub / Slack / esa 側にある。設計の全体像と根拠は Obsidian
`01_Inbox/2026-08-06-linear-command-layer-design.md`。

| やりたいこと        | コマンド                                                        |
| ------------------- | --------------------------------------------------------------- |
| 初期設定（ID解決）  | `bash scripts/linear-bootstrap.sh`                              |
| 起票                | `/linear-add`（対話skill。規約を自動適用する）                  |
| draft PR→Triage起票 | `bash scripts/linear-sweep.sh`（cron: 平日8:00）                |
| 夜間ディスパッチ    | `bash scripts/linear-dispatch-cron.sh`（cron: 火-土1:00）       |
| Slackスタンプ起票   | `/linear-slack-sweep`（cron: 平日8:10）                         |
| 起票済みかの確認    | `/linear-recall <スレURL or キーワード>`                        |
| 動作確認            | `bash scripts/test-linear-api.sh` ほか `test-linear-*.sh` 計6本 |

- 認証は `~/.config/linear/api-key`（chmod 600）、設定は `linear-bootstrap.sh` が生成する `config.json`
- 有効化フラグ: `~/.config/linear-sweep-enabled` / `~/.config/linear-dispatch-enabled` /
  `~/.config/linear-slack-sweep-enabled`
- **スイープはcronだけに頼らない。** WSL2のcronは**PCが停止していた時刻のジョブを実行せず**、
  anacronも入れていないため、8:00に起動していない日は丸ごと落ちる。
  `.config/fish/my/conf.d/14-linear-sweep.fish` がその日の最初の対話シェル起動時にも
  `--if-not-today` 付きで1回だけ走らせて取りこぼしを拾う（`$XDG_STATE_HOME` 相当の
  `~/.local/state/linear-sweep/last-run` で当日実行済みかを判定）。
  cronと併存しても `seen.txt` の重複排除があるので二重起票しない
- 共通ライブラリは `scripts/lib/linear-api.sh`。`linear_issue_create` は**assigneeを自動で自分にする**（未アサインだとMy Issuesに出ないため）

**リンクは Linear → 外部の一方向のみ。GitHub / Jira には一切書き戻さない。**
どちらもチームの共有物なので、個人のタスク管理都合のノイズを持ち込まない。「LinearのNSY-Xと
紐づけました」のような紐づけコメントもしない。ポインタはLinear側にだけ置けば足りる。

- スイープは読み取りAPIのみ使う（`gh` は `search`、Jira は GET、Slack は search と read_thread）
- 例外はagentが成果物として新規に作るPRだけ。そのPR本文にもLinearのidentifierを書かない
- `test-linear-sweep.sh` は gh stub が `search` 以外で呼ばれると落ちるので、これを検知できる
- Slack側の担保は許可リスト。`--allowedTools` に読み取り2つしか入れないことで書き込みを塞ぎ、
  `test-linear-slack-sweep-cron.sh` がその文字列を検査する

**stateの軸は「今ボールを誰が持っているか」。** 工程の進行度では切らない。進行度で切ると
state数が増え、かつ「進んでいるのに誰も動いていない」課題が見えなくなる。

| state | type | 意味 | ボール |
| --- | --- | --- | --- |
| `Triage` | triage | まだ見ていない（スイープが入れる） | — |
| `Todo` | unstarted | 受理済み。Cycleの候補 | 自分 |
| `In Progress` | started | 自分が手を動かしている。**対応内容の整理もここ** | 自分 |
| `AI Queued` | unstarted | AI待ち。dispatchの起動条件 | AI |
| `AI Running` | started | AI実行中 | AI |
| `My Review` | started | 自分の判断待ち（**AIの成果物**） | 自分 |
| `Waiting` | started | 他人待ち。チームレビュー・CI・返信待ち | 他人 |
| `Backlog` | backlog | Cycleを3回繰り越したもの（能動的に使わない） | — |

**`In Progress` と `My Review` の判定は一問。「その成果物をAIが作ったか」で、YESだけが
`My Review` に入る。** 唯一の入口は `AI Running → My Review`（dispatchがdraft PRを作った）で、
そこに四択（マージ / チームレビューへ / 修正指示 / 破棄）を掛ける。

- **自分の作業の確認待ちに専用stateを作らない。** 「実装は終わったが自分で見直したい」は
  `In Progress` のまま持つ。整理フェーズを `In Progress` に吸収したのと同じ理由で、
  stateを増やすと軸が「ボールの所持者」から「工程の進行度」に滑る。
  `In Progress` の出口は `AI Queued` / `Waiting` / `Done` の3つ
- **混ざると実害が出る。** WIP上限は `My Review` の件数を数えるので、非AI案件が入ると
  AIの生成量と無関係にdispatchが止まる。朝の判断タイムでも自分の作業に四択が当てはまらない。
  実際に `Todo → My Review` と `Waiting → My Review` の直行が起きた（どちらも許可遷移に無い）
- 検出は `/linear-triage` の整合チェック4）。**判定材料はPR URLの有無**（本文の `元URL:` か
  dispatchの完了コメント）。`My Review` は四択を掛ける場所なので、PRが無ければそもそも裁けない
- 許可遷移表とラベル体系（`role:*` / `em:*` / `src:*`）の全体は Obsidian
  `01_Inbox/2026-08-10-linear-state-label-design.md`

**Slackからの起票はスタンプ1つで完結する。** `:nishiyama_todo:` を押すと翌朝の
`linear-slack-sweep` が拾い、Triage に「元URL＋期待アウトカム」の形で積む。

- **Slack検索の `hasmy::emoji:` を候補生成に使い、リアクションの実在確認を最終防壁にする。**
  絵文字名が実在の英単語だと本文にもフォールバックする（`hasmy::ticket:` が本文の
  "air-ticketing" を拾った）。スレはどのみち読むので、この確認は追加コストゼロ
- **重複判定のキーは permalink ではなく `<channel_id>/<message_ts>`。** permalink は
  スレ内メッセージだと `?thread_ts=&cid=` が付いて同じメッセージでも文字列が揺れる
- **検索は日付で絞らない。** `after:` が効くのは**メッセージの投稿日**であって、スタンプを
  押した日ではない。窓を置くと古いスレを掘り返して押したものが窓の外に落ちて永久に拾われない。
  seen が冪等性を担保するので、全期間を何度スキャンしても二重起票にならず、
  cronが落ちた日は次回が勝手に拾い直す
- **「対象メッセージが見つからない」を「リアクション不在」と混同しない。** 返信が100件を超える
  スレでは対象が `read_thread` の出力に入らない。不在として扱うと、そのキーは毎回スキップされ
  seen にも入らないまま永久に起票されず、報告にも出ないので誰も気づけない。
  `oldest` を指定して読み直し、それでも出なければ判定不能として報告に出す
- **`role:*` / `em:*` は起票時にagentが推定して付ける。** 当初は朝のtriageに委ねていたが、
  triageが回らず**このスイープ起点の10件が全て未ラベルのまま残り**、`nippo-weekly` の
  クロス集計が `role:?` × `em:?` の1マスに潰れた。スレ全文を読んだ直後のagentは、朝に
  タイトルだけを見る人間より判断材料が多く、読解は手前の工程で済んでいるので追加コストも無い。
  draft PRスイープが `role:player` + `em:tech` を確定させているのと同じ扱いにした
- **推定が暫定であることは state = `Triage` が既に表しているので、専用のラベルは作らない。**
  外れていれば朝のtriageで直せばよく、傾向的なズレは `nippo-weekly` のサンプリング監査が拾う
- **Project の選択と親子付けは引き続きtriageに残す。** どちらも「既存の課題体系のどこに属すか」
  という**スレの外**の知識で決まるので、スレを読んだだけでは判断材料が足りない。
  ラベルの2軸だけがスレの中で閉じている
- **許可リストに無いラベル名は捨てて起票を続ける。** `linear_label_id` は未知キーで非0を返すため、
  そのまま渡すと `issueCreate` ごと落ちる。seen に入らないので次回も同じ失敗を繰り返し、
  そのメッセージだけ永久に起票されない。推定は付加価値であって起票の前提ではない
- **既存issueが見つかったとき（`commented`）はラベルを触らない。** 既にtriageを通って人間が
  付け直しているかもしれない分類を、スレを読み直しただけの機械が上書きしない
- **判断はagent、状態変更はスクリプト。** skillが要約とタイトルを作り、
  `scripts/linear-slack-sweep.sh` が重複チェック・起票・seen追記を持つ。
  夜間dispatchで push をスクリプト側に寄せたのと同じ分け方
- **`create` の flock は待つ（`-n` を付けない）。** skillはキーごとに別プロセスで呼ぶので、
  後発を捨てるとそのメッセージだけ起票されずに落ちる。`linear-sweep.sh` 側は同じスイープの
  二重起動なので捨ててよい、という違い
- **fish起動時フックには載せていない。** `claude -p` は数十秒かかるのでシェル起動を
  ブロックする。取りこぼしは `/linear-slack-sweep` を手で叩いて拾う
- **思い出し（`/linear-recall`）は確定と候補を区別する。** 元URL一致は確定、
  `searchIssues` の全文検索は候補。どちらも `includeArchived: true` を付ける
  （`autoArchivePeriod` が1ヶ月なので「昔やったはず」ほどアーカイブ側に居る）

**スイープ対象は自分のopen draft PRのみ。** 他者PRのレビュー依頼はGitHubの受信箱と二重管理に
なるうえ常時20〜30件あり、Triageが溢れて「人間が選別する受信箱」として機能しなくなる（初回
スイープの実測で27件中22件がレビュー依頼だった）。bot作成PRも除外する
（`LINEAR_SWEEP_EXCLUDE_AUTHORS`、既定 `*[bot]`）。

**夜間ディスパッチは「My Review」が `LINEAR_WIP_LIMIT`（既定10）件以上だと止まる。**
生成速度＞判断速度は仕組みが破綻しているシグナルなので、朝の判断タイムで捌いてから再開する。

- **起動条件は state = `AI Queued` の1点。ラベルは見ない**（パイプライン上の位置はstateで表し、
  ラベルと二重に持たない。`ai:blocked-human` だけは「そもそも委譲できない」属性なのでstateと直交する）
- dispatchは本文の内容で2モードに分かれる

| 本文              | モード | 動作                                                             |
| ----------------- | ------ | ---------------------------------------------------------------- |
| 既存PRのURLがある | 継続   | そのPRのブランチをcheckoutして続きを進める。**新規PRは作らない** |
| `repo:` 行のみ    | 新規   | `linear/<identifier>` ブランチを切って新規draft PRを作る         |

**子issueのタイトルのprefixがモードに対応する。** `draft仕上げ:` は既存draft PRを指すので継続、
`実装:` はPRがまだ無いので新規。新規ブランチ方式のままだと重複PRができていた。
継続モードはPRが `OPEN` でなければ実行しない。
`draft仕上げ:` は `linear-sweep.sh` の自動起票と `/linear-add` の手動起票の両方で使うが、
**どちらもPRが実在するものにしか付けない**（付けるとタイトルからモードを判別できなくなる）

- worktreeは `<repo>/.wt/linear-<identifier>` に作られる。**成功時（push/PR完了後）は
  dispatch自身がworktreeを掃除する**（newモードはブランチも `git branch -D`。continueモードの
  ブランチは既存PRのものなので残す）。pushでリモートに上がっているのでローカルに残す意味が薄い
- **失敗時（Todoへ差し戻す経路）はworktreeとブランチを調査用に意図的に残す。**
  newモードは着手前に前回の残骸を掃除する（残っていると `worktree add -b` がブランチ既存で失敗し、
  再実行が恒久的に BOUNCED になる）。残りきったものは `worktree-cleanup.sh` も拾う
- 成果物はdraft PRまで。マージは必ず人間

**push と PR作成はagentではなくスクリプトが行う。** Claude Code は `git push` を許可リストで
上書きできない（`--allowedTools` / settings.json の `permissions.allow` / `acceptEdits` /
`dontAsk` のいずれでも拒否される。`git ls-remote` のような読み取りは通る）。headlessのagentに
任せると必ずPR作成に到達しないため、役割を分ける。

| 担当       | 範囲                                                               |
| ---------- | ------------------------------------------------------------------ |
| agent      | 実装してworktree内でコミットするまで（`gh` を渡さない）            |
| スクリプト | `git push` と `gh pr create --draft`（素のbash。権限層を通らない） |

- **PR作成権限はagent実行前に確認する**（`gh repo view --json viewerPermission`）。
  無いまま走らせるとagentを丸ごと1回動かした末に最後だけ失敗する。判定不能な場合も実行しない
- `gh` は業務アカウントで認証されている。**個人リポジトリ（`rhi222/*`）は
  `READ` しか無いのでdispatchできない**（業務orgのリポジトリは `ADMIN`）
- コミットが0件ならpushもPR作成もしない（実装に到達しなかったとみなす）

**Cycleは1週間・月曜始まりの宣言型**（Jiraのsprint相当。2026-08-06に有効化）。

| 設定                                    | 値        | 理由                                                       |
| --------------------------------------- | --------- | ---------------------------------------------------------- |
| `cycleDuration`                         | 1（週）   | `nippo-weekly` の週次振り返りとリズムを合わせる            |
| `cycleStartDay`                         | **2**     | **これで月曜始まりになる**（1は日曜。実測で確認）          |
| `cycleIssueAutoAssignStarted/Completed` | false     | 自動で入ると「記録」になり、計画と実績の差分が取れない     |
| `issueEstimationType`                   | tShirt    | estimateは不確実さを測る。足せない量に数値の刻みは偽の精度 |

- **Cycleに載せるのは実作業単位。** 子issueがあれば子を、無ければ親を入れる。
  子を持つ親は入れない（二重計上になる）。親課題は複数Cycleにまたがる前提で、
  期限はProjectのtarget dateで追う
- `uncompletedIssuesUponClose` に繰り越しが残るので、**繰り越し回数が滞留の機械的な検出手段**になる
  （created日時より鋭い。「7/3から1ヶ月」のような滞留を3週目で拾える）

**estimateは所要時間ではなく不確実さを測る。** 3時間かかっても、やることが全部見えていれば `S`。
1段が1アクションに対応するよう、tShirtの5段階のうち **`S` / `M` / `L` の3つだけを使う**。

| 値  | 状態                                       | 決まる行動                             |
| --- | ------------------------------------------ | -------------------------------------- |
| `S` | 決めることが残っていない                   | そのまま載せる。AIに投げてよい         |
| `M` | 進め方に選択肢があり、選ぶところから始まる | 載せる。ただし最初の作業は「決める」   |
| `L` | 輪郭が曖昧で、分割しないと着手できない     | **Cycleに載せない。** 分割しろ、の印   |

- **`XS` と `XL` を使わないのは、段階を増やしても決まる行動が変わらないため。** 「1箇所だけ
  確かめれば動ける」は `S` と `M` の、「調査が先に要る」は `M` と `L` の、どちらに倒しても
  次の一手が同じだった
- **Cycleの合計pointはvelocityにならない。** 複雑さは足しても容量にならないので、消化量の指標には
  使わない。代わりに繰り越し回数と突き合わせると「`M` を付けたものが実際に繰り越しやすいか」を
  後から検証でき、付け方の精度が上がる
- **estimateは実作業単位にだけ付ける。** 親に付けるとCycleに載る子と二重に持つことになる
  （実際に NSY-65（親・2pt）と NSY-66（子・1pt）が両方Cycle 1に載り、同じ作業が3pt計上されていた）
- **内部値は `1/2/3/5/8` で、スケール外の数値はスナップされる**（実測で 4→5、13→8）。
  APIから付けるときは `S=2` / `M=3` / `L=5` を渡す。既存の `1` は `S` ではなく `XS` になるので、
  fibonacciから切り替えた際は付け直しが要る

**Project名のprefixは判定順で決める**（MECEにしない。先に当たった方が勝ち）。判定するのは
動機ではなく成果物。`worktree-cleanup.sh` の判定表と同じ方式。

| 順  | prefix            | 判定の問い                                       |
| --- | ----------------- | ------------------------------------------------ |
| 1   | `案件_`           | 特定の顧客案件のためだけの仕事か                 |
| 2   | `技術採用_`       | 採用活動そのものか（候補者を探す・口説く・選ぶ） |
| 3   | `組織課題_`       | 対象がヒトか（体制・育成・評価・自分の働き方）   |
| 4   | `QA_`             | 品質の確かめ方が変わるか                         |
| 5   | `プロダクト開発_` | 作るもの・作り方が変わるか                       |
| 6   | `other_`          | どれでもない（受け皿）                           |

issueは**親＝課題（Jiraチケットと1:1）/ 子＝工程**の2階層。**親の単位はJiraが決める**ので、
複数PRを1つの親にまとめる前に各PRのJiraキーが同一かを確認する（見た目の類似でまとめて
あとから割り直した実例あり）。ラベルは直交する2軸で、`role:player` / `role:manager`
（自分が手を動かしたか／人を動かしたか）と `em:people` / `em:tech` / `em:project` /
`em:product`（EMの職能）。Projectは「どの成果物の一部か」、labelは「自分のどの職能の仕事か」
で別の問いに答えるので競合しない。

Jiraの `summary` / `duedate` / 完了条件は claude.ai の Atlassian コネクタで読み込める
（`cloudId` は `~/.claude/local-context.md` を参照）。**`status` は同期しない**（Linearのstateは自分の
作業状態で、Jiraの進行状態とは別物）。この経路は対話セッション限定で、cronでは使えない。

**日報からのタスク転記は廃止した**（`nippo-add`）。転記ループは完了を検知せず、終わった
タスクがゾンビとして残り続けたため。実例として「執行役員会の発表準備」は7/3から8/6まで
1ヶ月転記され続けていたが完了済みだった。移行時の棚卸しでは滞留25件のうち11件が
「完了済み or もうやらない」だった。

---

この文書は [AGENTS.md](../AGENTS.md) から切り出したもの。AGENTS.md 側には要点と入口だけを残してある。
