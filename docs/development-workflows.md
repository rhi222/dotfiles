# 開発ワークフローと設定構造

## 設定の配置

- XDG対応ツールは `.config/<tool>/` に置く
- Neovimの自作namespaceはplugin名との衝突を避けるため `lua/my/` にする
- Neovimは `my/settings/`、`my/plugins/`、`my/commands/` へ責務別に分ける
- Fishは `.config/fish/my/conf.d/` へ読込順の番号を付けて機能別に置く
- runtimeとCLIはmiseで管理し、aptだけにあるものは `scripts/setup/apt-packages.txt` に置く

Fishの主要な順序はPATH → mise → history → environment → tide → alias → abbreviation →
tool integration → keybinding。追加時は既存番号の責務へ置き、番号を増やす前に統合できないか
確認する。

`ctrl-o` は折返し由来の改行を畳んでクリップボードを貼る（one-line pasteのo）。端末に出た
「本来1行」のコマンドやURLは、コピーすると改行が混入する。既定の `ctrl-v` は改行を保つので、
複数行のスクリプトやheredocはそちらで貼る。判定の根拠は `15-paste.fish` と
`__unwrap_wrapped_text.fish` のコメントにある。

## GitとPR

- commit messageは `.config/git/commit-conventions.txt` に従う
- stacked PRは手作業の `gh pr create --base <branch>` ではなく `gh stack` を使う
- `.config/claude/hooks/pr-base-guard.sh` が非default baseの `gh pr create` を検出してaskする
- backportなど正当な例外があるためguardはdenyではなくask
- default branchはlocalの `origin/HEAD` → `init.defaultBranch` → `main` の順で解決し、hookからnetworkへ出ない
- 壊れた入力、jq不在、git repo外ではhookをfail-openにしてPR作成自体を壊さない

設定変更後は `sync-claude-settings.sh` で同期してClaude Codeを再起動する。
テストは `bash tests/git/test-pr-base-guard.sh`。

## ghqとgf

`gf` は `ghq list` を `~/.cache/ghq-list` にcacheしてfzfへ渡す。fzf表示前にbackground更新し、
`ghq get|clone|rm|create|migrate` の成功直後には同期更新する。

- refresh内はwrapperを再帰しないよう `command ghq` を使う
- tmp名にfish PIDを含め、並行refreshの衝突を避ける
- 更新失敗時は既存cacheを維持し、stderrを `.err` に上書き保存する
- testはcache位置を差し替え、実cacheを触らない

## 文書予算

`scripts/repository/doc-budget.txt` がAGENTS.mdの全体行数と1セクション行数を制限する。

- 圧縮後の実測に合わせて上限を下げ、上げて解決しない
- `##` / `###` をsection境界とし、`####` は親に含める
- code block内の見出し風コメントはsectionに数えない
- 対象文書や宣言が無い新環境ではskipし、壊れた宣言はfailする

検査は `bash scripts/repository/doc-budget.sh`、テストは `bash tests/repository/test-doc-budget.sh`。

## Markdown整形

MarkdownはNeovimの保存時にPrettierで整形する。`proseWrap: preserve`として、日本語本文の
改行位置は執筆者の判断を維持する。

pre-commitはstage済みの内容だけを検査し、自動修正しない。部分stageでも未stageの編集を
巻き込まないため、indexから内容を読み出してPrettierの出力と比較する。手動での検査は
`bash scripts/repository/markdown-format.sh`、整形は末尾に`--fix`を付ける。

vendored skillはupstreamの書式を維持するため対象外とする。

## Docker

composeは `find_docker_compose` で探索し、`dc` / `dcl` / `dcu` / `dcd` のfish略語を使う。
掃除の仕様と安全条件は [docker-clean.md](docker-clean.md) を参照する。
