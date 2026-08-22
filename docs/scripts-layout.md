# scripts/ の構成と公開入口

`scripts/` を整理する（および一部を Go 製 `dotctl` へ移す）ときの基準を置く。
**移動する前に「誰が何を呼んでいるか」を固定するための文書**で、日々の使い方は [AGENTS.md](../AGENTS.md) の各機能の表を見る。

## 内部実装と公開入口

機能固有の実装は、ShellとGoのどちらも `internal/<feature>/` にまとめる。
`scripts/` 直下はcron、hook、skill、手動操作から呼ぶ互換entrypointとして維持する。
テストは `tests/<feature>/`、Go unit testは対象package、詳細仕様は `docs/` に置く。
配置規約のため `.config/<tool>/` に必要な設定は無理に移さず、feature READMEから参照する。

Shell実装も `internal/{linear,nippo,bootstrap,link,automation,session,update}/` に置く。
`scripts/linear-*.sh`、`scripts/nippo-*.sh`、`scripts/lib/{linear-api,nippo-paths}.sh` は公開APIなので残し、`internal/` の実装パスを外部から直接呼ばない。
新しいfeatureを作るのは、専用entrypoint・状態・テスト・仕様のうち複数を持つ機能に限る。
ファイル数が増えただけの設定toolごとには作らない。

## 現在の層

公開pathの安定性と実装のまとまりを両立するため、次の層に分ける。

| 層             | 例                                                   |
| -------------- | ---------------------------------------------------- |
| 公開entrypoint | `scripts/daily-update.sh`, `scripts/linear-sweep.sh` |
| 公開Shell API  | `scripts/lib/{linear-api,nippo-paths}.sh`            |
| Shell内部実装  | `internal/{linear,nippo,bootstrap}/`                 |
| Go内部実装     | `internal/{worktree,settings,skill}/`                |
| 宣言・template | `scripts/apt-packages.txt`, `scripts/doc-budget.txt` |
| black-box test | `tests/<feature>/test-*.sh`                          |

本数や行数は変更のたびに古くなるため、この文書では固定しない。
`scripts/` 直下をfeature別に移すとcronやskillを壊すため、直下は公開コマンド索引、`internal/` は実装を読む入口とする。

## 参照はどう壊れるか

`scripts/` 配下のパスは**散文として**参照されている。
実測で prod 側へ228件、test 側へ67件。
内訳は AGENTS.md と docs/ が168件、skill 本文・herdr の `config.toml`・`dotfilesLink.sh`・CI が60件。

**壊れても呼ばれた瞬間まで誰も気付かない。**
lint.sh は shell の中身、run-tests.sh は各スクリプトの振る舞い、doc-budget.sh は行数しか見ないので、「参照先が消えた」はどの検査にも掛からなかった。
cron と hook からの参照は黙って失敗する。

そこで `ref-check.sh` が参照先の実在を検査する（pre-commit と CI の二層。
`secret-scan.sh` と同じ構成で、主の防壁は pre-commit 側）。

- 同じ実体を指す書き方を揃える。
  `scripts/<name>.sh` / `$DOTFILES_DIR/scripts/<name>.sh` / `$HOME/scripts/<name>.sh` / `~/scripts/<name>.sh`（`~/scripts` は repo の `scripts/` への symlink）/ `$REPO_ROOT/scripts/<name>.sh` / `$SCRIPT_DIR/<name>.sh`
- **`$SCRIPT_DIR` は参照元のディレクトリ基準で解く。**
  テストを別階層へ移すと基準が変わるので、移動で壊れる参照の本体はここ
- **拾ってはいけないものが2つある。**
  `.config/herdr/scripts/status.sh` などの同名の別ディレクトリと、テスト内で `mktemp` した一時 repo を指す `$REPO/scripts/...`。
  どちらも拾うと恒久的に赤くなり、検査ごと無視される
- 例示・フィクスチャの架空パスは `example*` に寄せる。
  AGENTS.md の「例示・テストデータは架空名でよい」規約に合わせ、allowlist は glob 1行で許す。
  **1件ずつ足すと allowlist が「増える一方の除外リスト」になる**
- 走査は `git grep` 1回に畳んでいる。
  ファイル単位で `grep` を回した初版は 8.4秒かかった（500ファイル×4プロセス）。
  現在 0.47秒

## テストの置き場

テストは `tests/<feature>/test-*.sh`。
`internal/<feature>/` と同じ機能名を優先し、ShellかGoかでは分類しない。
Goの細かな分岐はpackage内のunit test、Shell内部APIと公開wrapper・hook・fish関数の契約は `tests/` で確認する。

| feature          | 中身                                                      |
| ---------------- | --------------------------------------------------------- |
| `repository/`    | lint / secret-scan / doc-budget / ref-check / test runner |
| `bootstrap/`     | `scripts/bootstrap.sh`                                    |
| `link/`          | `dotfilesLink.sh`                                         |
| `setup/`         | tool・pluginの導入                                        |
| `update/`        | 日次更新                                                  |
| `settings/`      | 設定同期とstatusline                                      |
| `privatebundle/` | ローカル設定の集約と運搬                                  |
| `doctor/`        | migrationと環境残骸                                       |
| `docker/`        | Docker掃除                                                |
| `wsl/`           | WSL掃除                                                   |
| `automation/`    | cronからのheadless実行基盤                                |
| `skills/`        | skillの追加・監査・vendoring                              |
| `worktree/`      | worktreeの初期化・掃除と `wt` / `wtd`                     |
| `git/`           | PR周り                                                    |
| `linear/`        | LinearのAPI・起票・ディスパッチ                           |
| `nippo/`         | 日報とesaレポート                                         |
| `notify/`        | トースト通知とクールダウン                                |
| `session/`       | herdr / nvimのセッション復元                              |
| `shell/`         | 複数featureに属さないfish関数                             |

- **`$SCRIPT_DIR` は対象を指さない。**
  テストは `REPO_ROOT` と `SCRIPTS_DIR` を自分の位置から起こして使う（`SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"`）
- **フィクスチャ本文に書く `$SCRIPT_DIR` は literal のまま置く。**
  移設時の一括置換でここを壊し、`ref-check.sh` の自テストが落ちて気付いた
- 新しいテストは対象の `internal/<feature>/` または公開入口と同じfeatureへ置く。
  どのfeatureでもない場合は `repository/` に寄せず、その仕組みの名前を作る

### 移していないもの（判断）

- **宣言ファイルは `scripts/` 直下に残す。**
  `apt-packages.txt` や `gh-extensions.txt` は利用者が編集する導線が散文に18箇所あり、消費側の `apt-setup.sh` / `setup-gh-extensions.sh` と隣接していることに意味がある。
  直下は55→45まで落ちたので、7個動かして得られるのは見た目だけ
- **テスト harness の共通化はしない。**
  `setup` / `teardown` / `check` が24本、`assert_eq` が22本、`assert_contains` が15本で重複しているのは事実だが、**Go 移植で最大の bash テストから順に消える予定**なので、いま共通化するとその多くが捨てる作業になる。
  移植を止める判断をした時点で改めて検討する
- フィクスチャ**データ**に共有価値のあるものは無かった（各テストが `mktemp` で自分の repo や `$HOME` を組み立てており、共有すると並列化の前提が崩れる）

## テストの実行

`run-tests.sh` は `test-*.sh` を並列で走らせるが、**出力は直列時と同じ** （テスト名の昇順・1本1行・失敗したものだけ出力を見せる）。
各テストの出力を個別ファイルへ溜め、全部終わってから順に流している。

**並列化の前提は各テストが `mktemp` で自分の作業場を作ること。**
固定パスへ書くテストを足すと隣と踏み合う。
破壊操作のテストは実 `$HOME`・実 ghq root・ 固定の `/tmp/<name>`・現在の worktree を対象にしない。

CI で動かせないものはテストファイル側の `# ci-skip:` で宣言する（実 nvim 設定と auto-session を要する2本がこれ）。

### 実測（16コア機）

| 対象                   | 所要    |
| ---------------------- | ------- |
| 全テスト（直列）       | 52秒    |
| 全テスト（並列・55本） | 9〜36秒 |
| `lint.sh`              | 約9秒   |
| `ref-check.sh`         | 0.47秒  |

並列時の幅は同時に走っている他の負荷による。
**この値は Go 移植の効果を判断する基準線**で、移植後に総コード量とテスト時間の両方が改善しなければ移植を止める。

## 関連する設計記録

| 対象 | 文書 |
| ---- | ---- |
| 公開スクリプトの引数と呼び出し元 | [scripts-command-index.md](scripts-command-index.md) |
| Go移植の評価とShellに残すAPI | [scripts-go-migration.md](scripts-go-migration.md) |
| env-residueとdcleanの実装判断 | [scripts-environment-decisions.md](scripts-environment-decisions.md) |
