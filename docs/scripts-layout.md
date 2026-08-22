# scripts/ の構成と公開入口

`scripts/` を整理する（および一部を Go 製 `dotctl` へ移す）ときの基準を置く。
**移動する前に「誰が何を呼んでいるか」を固定するための文書**で、日々の使い方は
[AGENTS.md](../AGENTS.md) の各機能の表を見る。

## ドメイン境界と公開入口

機能固有の実装は `domains/<domain>/` にまとめ、`scripts/` 直下はcron、hook、skill、
手動操作から呼ぶ互換entrypointとして維持する。テストは既存どおり
`tests/<domain>/`、詳細仕様は `docs/` に置く。配置規約のため `.config/<tool>/` に
置く必要がある設定は無理に移さず、domain READMEから参照する。

適用先は `domains/linear/` と `domains/nippo/`。`scripts/linear-*.sh`、
`scripts/nippo-*.sh`、`scripts/lib/{linear-api,nippo-paths}.sh` は公開APIなので残し、
実装パスを外部から直接呼ばない。
新しいdomainを作るのは、専用entrypoint・状態・テスト・仕様のうち複数を持つ機能に限る。
ファイル数が増えただけの設定toolごとには作らない。

## 現在の層

公開pathの安定性と実装のまとまりを両立するため、次の層に分ける。

| 層                     | 例                                        | 実測         |
| ---------------------- | ----------------------------------------- | ------------ |
| 公開entrypoint         | `daily-update.sh`, `linear-sweep.sh`      | 35本 2,549行 |
| 共有・互換Shell API    | `lib/cron-claude.sh`, `lib/nippo-paths.sh`| 8本 796行    |
| domain実装             | `domains/{linear,nippo}/`                 | 13本 1,490行 |
| 宣言・template         | `apt-packages.txt`, `doc-budget.txt`      | 7本          |
| 回帰test               | `tests/<domain>/test-*.sh`                | 56本         |

`scripts/` 直下は45entry。ここをdomain別に見せるために公開pathまで移すとcronやskillを
壊すため、直下はコマンド索引、`domains/` は実装を読む入口、と役割を分ける。

## 公開入口の一覧

「呼び出し元」は参照が**どの種類の場所から来ているか**。ここが移動時に壊れる面で、
`doc` 以外は壊れても静かに壊れる。

| タグ    | 参照元                                        |
| ------- | --------------------------------------------- |
| `doc`   | AGENTS.md / README.md / docs/                 |
| `skill` | Claude / Codex の skill 本文                  |
| `hook`  | git hook（`scripts/hooks/`）と Claude Code hook |
| `fish`  | fish 関数・`conf.d`                           |
| `ci`    | GitHub Actions                                |
| `link`  | `dotfilesLink.sh`                             |
| `cron`  | crontab 行（`*-cron.sh` 自身を含む）          |

### 検査

| スクリプト          | 行数 | 引数         | 呼び出し元          |
| ------------------- | ---- | ------------ | ------------------- |
| `lint.sh`           | 95   | `[--fix]`    | doc hook fish ci    |
| `secret-scan.sh`    | 112  | `--staged` / `--tree` | doc hook ci link |
| `doc-budget.sh`     | 147  | `[--staged]` | doc hook ci         |
| `ref-check.sh`      | 133  | なし         | hook ci             |
| `run-tests.sh`      | 169  | `[--ci]`     | doc ci              |
| `migration-check.sh`| 24   | `[<dir>...]` | doc                 |
| `env-residue.sh`    | 25   | なし         | doc                 |

### セットアップ（新環境の立ち上げ）

| スクリプト               | 行数 | 引数           | 呼び出し元 |
| ------------------------ | ---- | -------------- | ---------- |
| `apt-setup.sh`           | 14   | なし           | doc link   |
| `setup-claude-skills.sh` | 196  | `[--dry-run]`  | doc        |
| `setup-fish-plugins.sh`  | 187  | `[--dry-run]`  | doc        |
| `setup-gh-extensions.sh` | 139  | `[--dry-run]`  | doc        |
| `setup-yazi-plugins.sh`  | 144  | `[--dry-run]`  | doc link   |
| `linear-bootstrap.sh`    | 55   | なし           | doc link   |

### 同期・運搬

| スクリプト                  | 行数 | 引数                              | 呼び出し元 |
| --------------------------- | ---- | --------------------------------- | ---------- |
| `sync-claude-settings.sh`   | 23   | `status`\|`pull`\|`push [--force]`| doc link   |
| `sync-windows-settings.sh`  | 25   | `status`\|`pull`\|`push` `[target]`| doc       |
| `private-bundle.sh`         | 25   | `adopt [--execute]`\|`export`\|`import <zip>`\|`status` | doc link |

### 更新

| スクリプト         | 行数 | 引数 | 呼び出し元 |
| ------------------ | ---- | ---- | ---------- |
| `daily-update.sh`  | 295  | なし | doc hook   |

### skill 管理

| スクリプト        | 行数 | 引数                                         | 呼び出し元 |
| ----------------- | ---- | -------------------------------------------- | ---------- |
| `skill-add.sh`    | 76   | `<owner/repo> <skill>`                       | doc        |
| `skill-audit.sh`  | 24   | `[--quiet] <skill-dir>`                      | doc        |
| `skill-vendor.sh` | 25   | `add <repo> <sub-path> [name]`\|`update`\|`status`\|`list` | doc |

### worktree

| スクリプト             | 行数 | 引数                            | 呼び出し元         |
| ---------------------- | ---- | ------------------------------- | ------------------ |
| `worktree-init.sh`     | 27   | `[--dry-run] [<path>]`          | doc skill hook link|
| `worktree-cleanup.sh`  | 28   | `[--size] [--execute] [--force]`| doc skill          |

### 掃除

| スクリプト        | 行数 | 引数          | 呼び出し元 |
| ----------------- | ---- | ------------- | ---------- |
| `wsl-cleanup.sh`  | 24   | `[--execute]` | doc        |

### Linear

| スクリプト                     | 行数 | 引数              | 呼び出し元           |
| ------------------------------ | ---- | ----------------- | -------------------- |
| `linear-sweep.sh`              | 157  | なし              | doc skill fish link  |
| `linear-slack-sweep.sh`        | 169  | `[unseen <key>]`  | doc skill            |
| `linear-slack-sweep-cron.sh`   | 44   | なし              | doc cron             |
| `linear-interview-prep.sh`     | 160  | `[unseen <id>]`   | doc skill cron       |
| `linear-dispatch-cron.sh`      | 324  | なし              | doc skill link cron  |

### 日報・レポート

| スクリプト               | 行数 | 引数 | 呼び出し元           |
| ------------------------ | ---- | ---- | -------------------- |
| `nippo-check.sh`         | 140  | なし | doc hook link cron   |
| `nippo-cron.sh`          | 54   | なし | doc link cron        |
| `nippo-create-cron.sh`   | 59   | なし | doc cron             |
| `nippo-draft-cron.sh`    | 44   | なし | doc cron             |
| `esa-weekly-cron.sh`     | 37   | なし | doc skill cron       |

### セッション復元

| スクリプト           | 行数 | 引数          | 呼び出し元 |
| -------------------- | ---- | ------------- | ---------- |
| `herdr-restore.sh`   | 211  | `[--dry-run]` \| `[--status]` | doc fish |

## 参照はどう壊れるか

`scripts/` 配下のパスは**散文として**参照されている。実測で prod 側へ228件、
test 側へ67件。内訳は AGENTS.md と docs/ が168件、skill 本文・herdr の
`config.toml`・`dotfilesLink.sh`・CI が60件。

**壊れても呼ばれた瞬間まで誰も気付かない。** lint.sh は shell の中身、
run-tests.sh は各スクリプトの振る舞い、doc-budget.sh は行数しか見ないので、
「参照先が消えた」はどの検査にも掛からなかった。cron と hook からの参照は
黙って失敗する。

そこで `ref-check.sh` が参照先の実在を検査する（pre-commit と CI の二層。
`secret-scan.sh` と同じ構成で、主の防壁は pre-commit 側）。

- 同じ実体を指す書き方を揃える。`scripts/<name>.sh` /
  `$DOTFILES_DIR/scripts/<name>.sh` / `$HOME/scripts/<name>.sh` /
  `~/scripts/<name>.sh`（`~/scripts` は repo の `scripts/` への symlink）/
  `$REPO_ROOT/scripts/<name>.sh` / `$SCRIPT_DIR/<name>.sh`
- **`$SCRIPT_DIR` は参照元のディレクトリ基準で解く。** テストを別階層へ移すと
  基準が変わるので、移動で壊れる参照の本体はここ
- **拾ってはいけないものが2つある。** `.config/herdr/scripts/status.sh` などの
  同名の別ディレクトリと、テスト内で `mktemp` した一時 repo を指す
  `$REPO/scripts/...`。どちらも拾うと恒久的に赤くなり、検査ごと無視される
- 例示・フィクスチャの架空パスは `example*` に寄せる。AGENTS.md の
  「例示・テストデータは架空名でよい」規約に合わせ、allowlist は glob 1行で許す。
  **1件ずつ足すと allowlist が「増える一方の除外リスト」になる**
- 走査は `git grep` 1回に畳んでいる。ファイル単位で `grep` を回した初版は
  8.4秒かかった（500ファイル×4プロセス）。現在 0.47秒

## テストの置き場

テストは `tests/<domain>/test-*.sh`。**ドメインは上の「公開入口の一覧」の役割
グループに揃えている**（同じリポジトリに taxonomy を2つ作らないため）。

| ドメイン    | 本数 | 中身                                               |
| ----------- | ---- | -------------------------------------------------- |
| `checks/`   | 7    | lint / secret-scan / doc-budget / ref-check / run-tests / migration-check / env-residue |
| `setup/`    | 6    | 新環境の立ち上げと日次更新                         |
| `settings/` | 4    | 設定の同期・運搬・statusline                       |
| `skills/`   | 3    | skill の追加・監査・vendoring                      |
| `worktree/` | 4    | worktree の初期化・掃除と `wt` / `wtd`             |
| `git/`      | 3    | PR 周り（`mv2main` / `open-pr` / base ガード）     |
| `linear/`   | 7    | Linear の API・起票・ディスパッチ                  |
| `nippo/`    | 5    | 日報と esa レポート                                |
| `notify/`   | 3    | トースト通知とクールダウン                         |
| `session/`  | 6    | herdr / nvim のセッション復元                      |
| `shell/`    | 4    | fish 関数（fzf 連携・`fkill` / `gf`）              |
| `cleanup/`  | 2    | WSL と Docker の掃除                               |
| `cron/`     | 1    | cron からの claude ヘッドレス実行の土台            |

- **`$SCRIPT_DIR` は対象を指さない。** テストは `REPO_ROOT` と `SCRIPTS_DIR` を
  自分の位置から起こして使う（`SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"`）
- **フィクスチャ本文に書く `$SCRIPT_DIR` は literal のまま置く。** 移設時の一括置換で
  ここを壊し、`ref-check.sh` の自テストが落ちて気付いた
- 新しいテストは対象スクリプトと同じ役割グループへ置く。どのグループでもないなら
  `checks/` ではなく、その仕組みの名前で新しいディレクトリを作る（`cron/` がその例）

### 移していないもの（判断）

- **宣言ファイルは `scripts/` 直下に残す。** `apt-packages.txt` や
  `gh-extensions.txt` は利用者が編集する導線が散文に18箇所あり、消費側の
  `apt-setup.sh` / `setup-gh-extensions.sh` と隣接していることに意味がある。
  直下は55→45まで落ちたので、7個動かして得られるのは見た目だけ
- **テスト harness の共通化はしない。** `setup` / `teardown` / `check` が24本、
  `assert_eq` が22本、`assert_contains` が15本で重複しているのは事実だが、
  **Go 移植で最大の bash テストから順に消える予定**なので、いま共通化すると
  その多くが捨てる作業になる。移植を止める判断をした時点で改めて検討する
- フィクスチャ**データ**に共有価値のあるものは無かった（各テストが
  `mktemp` で自分の repo や `$HOME` を組み立てており、共有すると並列化の前提が崩れる）

## テストの実行

`run-tests.sh` は `test-*.sh` を並列で走らせるが、**出力は直列時と同じ**
（テスト名の昇順・1本1行・失敗したものだけ出力を見せる）。各テストの出力を
個別ファイルへ溜め、全部終わってから順に流している。

**並列化の前提は各テストが `mktemp` で自分の作業場を作ること。** 固定パスへ書く
テストを足すと隣と踏み合う。破壊操作のテストは実 `$HOME`・実 ghq root・
固定の `/tmp/<name>`・現在の worktree を対象にしない。

CI で動かせないものはテストファイル側の `# ci-skip:` で宣言する
（実 nvim 設定と auto-session を要する2本がこれ）。

### 実測（16コア機）

| 対象                      | 所要      |
| ------------------------- | --------- |
| 全テスト（直列）          | 52秒      |
| 全テスト（並列・55本）    | 9〜36秒   |
| `lint.sh`                 | 約9秒     |
| `ref-check.sh`            | 0.47秒    |

並列時の幅は同時に走っている他の負荷による。**この値は Go 移植の効果を判断する
基準線**で、移植後に総コード量とテスト時間の両方が改善しなければ移植を止める。

## Go 移植のパイロット結果（worktree-cleanup）

`worktree-cleanup.sh` を `dotctl worktree cleanup` へ移した結果。**この数字が
「他のスクリプトも移すか」の判断材料**で、移植を止める判断もここに基づく。

### 実測

| 指標                       | 移植前            | 移植後                                    | 差       |
| -------------------------- | ----------------- | ----------------------------------------- | -------- |
| 実装                       | 518行（Shell）    | 28（wrapper）+ 845（Go）+ 81（配線）      | **+84%** |
| テスト合計                 | 651行             | 253（統合）+ 886（Go）                    | **+75%** |
| うち Shell テスト          | 651行             | 253行                                     | **-61%** |
| 検査ケース数               | 103               | 33（統合）+ 92（Go）                      | +21%     |
| 分岐テストの所要           | 実 git が必須     | 0.007秒（プロセス起動 0）                 | —        |
| 実行時間（制御環境・5wt）  | 48ms              | 30ms                                      | **-37%** |
| skew 検知の追加コスト      | —                 | 3ms                                       | —        |

実運用の実行時間（約1秒）は `gh pr list` のネットワーク待ちが支配するので、
両実装で差が出ない。**速度は判断材料にならない。**

### 評価基準への当てはめ

| Phase 0 で決めた基準                             | 結果 |
| ------------------------------------------------ | ---- |
| 既存の安全条件と公開インターフェースを維持できる | ✓ 4モードでバイト単位一致。呼び出し口は0変更 |
| 分岐の unit test が外部コマンドなしで書ける      | ✓ `Classify` は純粋関数。19ケースが 0.007秒 |
| Shell テストを含む総コード量または認知負荷が減る | △ 総量は増えた。認知負荷は下がった |
| 通常利用時の起動時間が許容範囲                   | ✓ 制御環境で 37% 速い |
| bootstrap・cron で新しい不安定要因を増やさない   | △ ビルド手順と skew という概念が増えた |

### 何が良くなったか

- **判定が1つの表になった。** Shell 版は `classify_worktree` の中で git を呼び
  printf で表示まで済ませていたので、分岐だけを検査する手段が無かった。
  いまは19行の表を読めば判定の全体が分かる
- **移植で2つの脆さが消えた。** TAB が IFS の空白文字であるために detached の
  空 branch が畳まれてフィールドがずれる問題と、表示用の配列と削除用の配列が
  別々にあって食い違いうる構造
- **一致を証明できるようになった。** 実 git のフィクスチャで4モードの出力を
  バイト比較している。Shell だけの頃は「壊していないこと」を目視で確認していた

### 何が悪くなったか

- **総コード量が 1.8 倍になった。** 型宣言・エラー処理・doc コメントの分。
  同じ振る舞いにこれだけ払っている
- **言語が2つになった。** 読む側は wrapper → Go の2段を追う必要がある
- **ビルド手順が増えた。** `setup-dotctl.sh` の実行が bootstrap に入り、
  `git pull` 後の再ビルド漏れという新しい失敗モードができた
  （日次の自動再ビルドと skew 警告で塞いではいる）

### 残りの候補への当てはめ

パイロットの利得は**「複雑な判定がある」ところに効く**。`worktree-cleanup` は
9通りの分岐と順序依存を持っていたのでそこが効いた。残りの候補はその点が薄い。

| 候補                       | 行数 | 中身の性質                        | 判定の複雑さ |
| -------------------------- | ---- | --------------------------------- | ------------ |
| `skill-vendor.sh`          | 431  | metadata・検証・複数操作          | 中           |
| `private-bundle.sh`        | 368  | zip・permission・退避判定         | 低（I/O 中心）|
| `sync-windows-settings.sh` | 259  | `jq` 正規化と同期計画             | 低（I/O 中心）|
| `wsl-cleanup.sh`           | 236  | 候補判定と破壊操作の境界          | 中           |

## Shell に残す2つのライブラリ（評価の結論）

`scripts/lib/` に残っているのは、Claude skill が `source` して関数を呼ぶ2本。
**移せるかを評価した結果、どちらも残す。**

### `lib/nippo-paths.sh`（64行・7関数）

日報のパス解決。`${d:0:4}` のような文字列切り出しだけで、外部コマンドは
`date` 1つ。6 skill + 3 script + cron から使われている。

**移さない理由が3つある。**

- **プロセス生成を避けているのが設計。** 本文に「date(1) を通さないのは、
  呼び出し回数が多く、かつ入力が常に YYYY-MM-DD 固定だからプロセス生成に
  見合わないため」と書いてある。`dotctl` 呼び出しに置き換えると、
  作者が意図的に避けたプロセス生成を1回あたり1つ足すことになる
- **dotctl が日報フローの必須依存になる。** いまは bash だけで動くので、
  新環境でも Go を入れる前から日報が書ける
- **skill 6本の frontmatter と cron 3本の `--allowedTools` を触ることになる。**
  cron は skill とは別に許可リストを持っているので、片方だけ直すと
  「手動では動くのに自動実行だけ権限で落ちる」が起きる

得られるのは64行の文字列結合を型付きにすることだけで、払うものが大きい。

### `lib/linear-api.sh`（182行・11関数）

Linear の GraphQL 呼び出し。`curl` + `jq` で、6 skill + 5 script から使われている。

**中身は確かに複雑な shell だが、インターフェースが移植に向かない。**

- `linear_gql` は**任意の GraphQL を文字列で受ける**（skill から16箇所、複数行の
  クエリを渡している）。CLI の argv 越しに多行クエリを通すのは、いまより脆い
- `linear_config` は**jq のフィルタを引数で受ける**（`.states["Todo"]` など）。
  Go 側で受けても jq を呼ぶことになり、置き換えの意味が薄い
- 実装だけ Go にして関数名を wrapper として残す手はあるが、移るのは curl と
  エラー処理の30行ほど。**Linear はタスクの司令塔**なので、この規模の利得と
  引き換えに壊す risk は釣り合わない

plan の「当面 Shell に残す」表がこの2本を挙げていたのは妥当だった、という結論。
**そのため Linear の状態変更コマンド（`linear-dispatch-cron.sh` ほか）も
移していない。** あれはこの評価とセットで着手する前提だった。

## 残骸チェックの判断（env-residue）

`dotctl doctor residue` が見るのは3種類。**既存のどのチェックにも掛からない
種類の drift を埋めるためのもの**で、`doctor migration` は「リポジトリの作業状態」
専用で環境は見ない。実際にこの3種類を全部踏んだ（追跡外の
`fish_user_key_bindings.fish` で Ctrl+R の修正が端末をまたぐたび戻り、
vendored skill 6本が古い gh 版に隠されていた）。

| 何を見るか                                   | なぜ                                                     |
| -------------------------------------------- | -------------------------------------------------------- |
| `~/.fzf/` と `~/.fzf.bash`                   | mise 管理と二重。PATH 順で古い版を掴む端末が出る         |
| `~/.config/fish/functions/` の追跡外ファイル | Ctrl+R の担当が端末ごとに割れる原因になる                |
| `~/.claude` `~/.codex` `~/.agents` の skill  | 宣言に無いもの、vendored なのに実ディレクトリになったもの |

- **fisher の判定は名前の規約ではなく fisher 自身が持つ一覧で行う。** fisher は
  プラグインごとに universal 変数 `_fisher_<plugin>_files` へインストールした
  ファイルを記録している。「`_` 始まりはプラグイン」で切った初版は tide の
  `fish_prompt` / `fish_mode_prompt` / `tide`、`fisher` 本体、fzf.fish の
  `fzf_configure_bindings` を**誤検知した（実環境で5件）**。公開関数は普通の名前を持つ
- **一覧が引けない環境では名前の規約に落とす。** fish が無ければ fish 関数の
  残骸も問題にならないので、報告漏れより誤検知を避ける側に倒す
- **skill の宣言が読めないときは skill の判定を丸ごと諦める。** 読めないまま
  「宣言に無い」と言うと、正しく入っているものまで残骸に見える
- **見つかっても exit 0。** 残骸があること自体は壊れている状態ではなく、放置すると
  事故になりうる状態。毎日 FAILED が飛ぶと無視されるようになる
- 件数は機械可読サマリ行（`env-residue: FOUND=N`）から取る。表示の体裁を変えても
  呼び出し側が壊れないようにするため（`worktree-cleanup.sh` と同じ作り）

## docker 掃除（dclean）を Go へ移した理由

`dclean` は fish 関数だったが、判定の中身が「複雑な logic を shell でやっている」
最大の残りだった（fish 362行 + ヘルパー5本 + テスト905行）。

移した先は `dotctl docker clean` / `notice` / `stale` / `refresh`。**`dclean` という
呼び名は残す**（fish の補完と指の記憶がこの名前に紐づいているため）。

掃除範囲・閾値・通知の判定（`df` の Reclaimable の読み方、`--builder` / `--filter until=` の
実測、orphan 判定など）は [docker-clean.md](docker-clean.md) が正で、移植で全て維持した。
ここには fish 側に残った wrapper の注意だけを置く。

### fish 側で気を付けた2点

- **`string pad` は表示幅で詰める。** Go の `fmt` はルーン数、bash の `printf` は
  バイト数なので、どちらを使っても日本語ラベルの桁が崩れる。表示幅を数える関数を
  自前で持ち、fish の `string pad` と一致することをテストで固定した
- **設定変数の受け渡しに `string collect` が要る。** fish のコマンド置換は改行で
  分割するので、付けないと除外グロブが2要素になり `env` が2つ目をコマンド名として
  扱う（実際に踏んだ）
