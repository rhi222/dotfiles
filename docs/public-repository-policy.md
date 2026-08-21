# publicリポジトリの機密情報ポリシー

このリポジトリへ社名、社内host、社内repository名、Jira project key、案件code、顧客略号を
入れない。実値はrepo外またはgitignore対象へ置き、repoにはplaceholder入り `.example` だけを置く。

| 内容 | 実体 | 雛形 |
| ---- | ---- | ---- |
| Jira/GitLab/esaなどの社内context | `~/.claude/local-context.md` | `.config/claude/local-context.md.example` |
| 機密語辞書 | `~/.config/dotfiles/secret-patterns.txt` | `scripts/secret-patterns.txt.example` |
| nvimのHTTPS非対応host | `my/local_config.lua` | `my/local_config.lua.example` |
| dclean除外 | `99-local.fish` | なし |
| 社内AHK snippet | `snippets-local.ahk`, `ahk-snippets/js/` | なし |
| 社内pluginとmarketplace | 実 `settings.json`。同期時にmask | なし |
| 社内system名で発動するskill | skill directory全体をignore | なし |

例示とtestは `example-org` / `example-repo` / `CUST-A` など架空値を使う。ただし実在serviceの
subdomain形式は汎用辞書に一致しうるため、`slack.example.com` のような予約domainへ寄せる。

## 検査

`scripts/secret-scan.sh` を二層で使う。

| 層 | mode | 辞書 |
| -- | ---- | ---- |
| pre-commit | `--staged` | 実体辞書 |
| GitHub Actions | `--tree` | `.example` の汎用pattern |

- CIへ実体辞書を渡さない。public logに辞書そのものが漏れるため
- 辞書が無い新環境は警告して通し、`dotfilesLink.sh` が雛形を作る
- 内容だけでなくpath名も検査する
- 社内名を含む対象は、名前を `.gitignore` に書かず親directory単位でignoreする
- `--no-verify` は原則使わない

動作確認は `bash tests/checks/test-secret-scan.sh`。

