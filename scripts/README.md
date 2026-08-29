# scripts

公開コマンドはfeature別に置く。詳細な引数と呼び出し元は
[scripts-command-index.md](../docs/scripts-command-index.md) を参照する。

| directory     | 役割                                     |
| ------------- | ---------------------------------------- |
| `repository/` | lint、test、secret・文書・参照検査       |
| `setup/`      | 新環境とtool・pluginの導入、宣言ファイル |
| `settings/`   | 設定同期とprivate bundle                 |
| `update/`     | 日次更新                                 |
| `doctor/`     | 移行・環境残骸の診断                     |
| `skills/`     | agent skillの追加・監査・vendoring       |
| `worktree/`   | worktreeの初期化・掃除                   |
| `linear/`     | Linear自動化                             |
| `nippo/`      | 日報・レポート自動化                     |
| `session/`    | herdr session復元                        |
| `wsl/`        | WSL cleanup                              |
| `lib/`        | skill・hookがsourceする公開Shell API     |
| `hooks/`      | Git hook                                 |

repo内からは `scripts/<feature>/<command>.sh` を呼ぶ。
旧 `~/scripts/<name>` は `dotfilesLink.sh` が
[`compat-links.txt`](compat-links.txt) から生成する互換linkであり、repo直下へ旧名wrapperは原則置かない。
`setup-dotctl.sh` だけは、更新前の `dotctl` が埋め込んだrepo pathから
新しい `scripts/setup/dotctl.sh` へ自己更新するためのbootstrap wrapperとして維持する。
