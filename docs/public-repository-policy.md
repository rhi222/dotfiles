# publicリポジトリの機密情報ポリシー

このリポジトリへ社名、社内host、社内repository名、Jira project key、案件code、顧客略号を
入れない。実値はrepo外またはgitignore対象へ置き、repoにはplaceholder入り `.example` だけを置く。

| 内容 | 実体 | 雛形 |
| ---- | ---- | ---- |
| Jira/GitLab/esaなどの社内context | `~/.claude/local-context.md` | `.config/claude/local-context.md.example` |
| 機密語辞書 | `~/.config/dotfiles/secret-patterns.txt` | `scripts/secret-patterns.txt.example` |
| nvimのHTTPS非対応host | `my/local_config.lua` | `my/local_config.lua.example` |
| psqlのprod/stg判定 | `~/.config/psql/psqlrc.local` | `.config/psql/psqlrc.local.example` |
| dclean除外 | `99-local.fish` | なし |
| 社内AHK snippet | `snippets-local.ahk`, `ahk-snippets/js/` | なし |
| 社内pluginとmarketplace | 実 `settings.json`。同期時にmask | なし |
| 社内system名で発動するskill | skill directory全体をignore | なし |

例示とtestは `example-org` / `example-repo` / `CUST-A` など架空値を使う。ただし実在serviceの
subdomain形式は汎用辞書に一致しうるため、`slack.example.com` のような予約domainへ寄せる。

## 検査

`scripts/repository/secret-scan.sh` を三層で使う。

| 層 | mode | 辞書 |
| -- | ---- | ---- |
| pre-commit | `--staged` | 実体辞書 |
| 手元の全変更確認 | `--worktree` | 実体辞書 |
| GitHub Actions | `--tree` | `.example` の汎用pattern |

- CIへ実体辞書を渡さない。public logに辞書そのものが漏れるため
- 辞書が無い新環境は警告して通し、`scripts/bootstrap.sh` が雛形を作る
- 内容だけでなくpath名も検査する
- commit前に未追跡ファイルを含めて確認するときは `--worktree` を使う。ignore済みファイルは対象外
- 社内名を含む対象は、名前を `.gitignore` に書かず親directory単位でignoreする
- `--no-verify` は原則使わない

## 既に公開された履歴

**HEADから消しても過去のcommitは読める。** 混入に気づいた時点で、履歴を書き換えるか
受容するかを決める。既定は受容。force pushはclone済みの他端末とworktreeを壊し、
GitHub側のcacheやforkも消せないため、資格情報でない限り代償が見合わない。

受容した場合の後始末は次の2つ。

- 該当語を実体辞書へ追加し、同じ値が再びcommitされるのをpre-commitで止める
- 実値をrepo外へ出し、repoには `.example` だけを残す

`psqlrc` の案件固有値（DB名、DBユーザー名、判定に使うport）はこの経路で受容済み。

動作確認は `bash tests/repository/test-secret-scan.sh`。
