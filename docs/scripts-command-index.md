# scripts/の公開コマンド索引

[scripts-layout.md](scripts-layout.md) から分割した、公開スクリプトの引数と呼び出し元の一覧。
リポジトリ内では以下の正規pathを使う。旧 `~/scripts/<name>` は [`scripts/compat-links.txt`](../scripts/compat-links.txt) が維持する。

## 正規入口の一覧

「呼び出し元」は参照が**どの種類の場所から来ているか**。
ここが移動時に壊れる面で、`doc` 以外は壊れても静かに壊れる。

| タグ    | 参照元                                          |
| ------- | ----------------------------------------------- |
| `doc`   | AGENTS.md / README.md / docs/                   |
| `skill` | Claude / Codex の skill 本文                    |
| `hook`  | git hook（`scripts/hooks/`）と Claude Code hook |
| `fish`  | fish 関数・`conf.d`                             |
| `ci`    | GitHub Actions                                  |
| `link`  | `dotfilesLink.sh`                               |
| `boot`  | `scripts/setup/bootstrap.sh`                    |
| `cron`  | crontab 行（`*-cron.sh` 自身を含む）            |

### 検査

| スクリプト                              | 引数                     | 呼び出し元       |
| --------------------------------------- | ------------------------ | ---------------- |
| `scripts/repository/lint.sh`            | `[--fix]`                | doc hook fish ci |
| `scripts/repository/markdown-format.sh` | `[--fix]` / `[--staged]` | doc hook ci      |
| `scripts/repository/secret-scan.sh`     | `--staged` / `--tree`    | doc hook ci link |
| `scripts/repository/doc-budget.sh`      | `[--staged]`             | doc hook ci      |
| `scripts/repository/ref-check.sh`       | なし                     | hook ci          |
| `scripts/repository/run-tests.sh`       | `[--ci]`                 | doc ci           |
| `scripts/doctor/migration.sh`           | `[<dir>...]`             | doc              |
| `scripts/doctor/residue.sh`             | なし                     | doc              |

### セットアップ（新環境の立ち上げ）

| スクリプト                       | 引数                               | 呼び出し元 |
| -------------------------------- | ---------------------------------- | ---------- |
| `scripts/setup/bootstrap.sh`     | なし                               | doc        |
| `scripts/setup/agent-plugins.sh` | `[--dry-run] [--replace-upstream]` | doc        |
| `scripts/setup/apt.sh`           | なし                               | doc boot   |
| `scripts/setup/dotctl.sh`        | なし                               | doc boot   |
| `scripts/setup/claude-skills.sh` | `[--dry-run]`                      | doc        |
| `scripts/setup/fish-plugins.sh`  | `[--dry-run]`                      | doc        |
| `scripts/setup/gh-extensions.sh` | `[--dry-run]`                      | doc        |
| `scripts/setup/yazi-plugins.sh`  | `[--dry-run]`                      | doc boot   |
| `scripts/linear/bootstrap.sh`    | なし                               | doc link   |

### 同期・運搬

| スクリプト                           | 引数                                                    | 呼び出し元 |
| ------------------------------------ | ------------------------------------------------------- | ---------- |
| `scripts/settings/sync-claude.sh`    | `status`\|`pull`\|`push [--force]`                      | doc boot   |
| `scripts/settings/sync-windows.sh`   | `status`\|`pull`\|`push` `[target]`                     | doc        |
| `scripts/settings/private-bundle.sh` | `adopt [--execute]`\|`export`\|`import <zip>`\|`status` | doc link   |

### 更新

| スクリプト                | 引数 | 呼び出し元 |
| ------------------------- | ---- | ---------- |
| `scripts/update/daily.sh` | なし | doc hook   |

### skill 管理

| スクリプト                 | 引数                                                                        | 呼び出し元 |
| -------------------------- | --------------------------------------------------------------------------- | ---------- |
| `scripts/skills/add.sh`    | `<owner/repo> <skill>`                                                      | doc        |
| `scripts/skills/audit.sh`  | `[--quiet] <skill-dir>`                                                     | doc        |
| `scripts/skills/vendor.sh` | `add <repo> <sub-path> [name]`\|`update <name> [name...]`\|`status`\|`list` | doc        |

### agent plugin管理

| スクリプト                  | 引数                                        | 呼び出し元 |
| --------------------------- | ------------------------------------------- | ---------- |
| `scripts/plugins/vendor.sh` | `status [--no-network]`\|`update <name>...` | doc        |

### worktree

| スクリプト                    | 引数                             | 呼び出し元          |
| ----------------------------- | -------------------------------- | ------------------- |
| `scripts/worktree/init.sh`    | `[--dry-run] [<path>]`           | doc skill hook link |
| `scripts/worktree/cleanup.sh` | `[--size] [--execute] [--force]` | doc skill           |

### 掃除

| スクリプト               | 引数          | 呼び出し元 |
| ------------------------ | ------------- | ---------- |
| `scripts/wsl/cleanup.sh` | `[--execute]` | doc        |

### Linear

| スクリプト                           | 引数             | 呼び出し元          |
| ------------------------------------ | ---------------- | ------------------- |
| `scripts/linear/sweep.sh`            | なし             | doc skill fish link |
| `scripts/linear/slack-sweep.sh`      | `[unseen <key>]` | doc skill           |
| `scripts/linear/slack-sweep-cron.sh` | なし             | doc cron            |
| `scripts/linear/interview-prep.sh`   | `[unseen <id>]`  | doc skill cron      |
| `scripts/linear/dispatch-cron.sh`    | なし             | doc skill link cron |

### 日報・レポート

| スクリプト                         | 引数 | 呼び出し元         |
| ---------------------------------- | ---- | ------------------ |
| `scripts/nippo/check.sh`           | なし | doc hook link cron |
| `scripts/nippo/notify-cron.sh`     | なし | doc link cron      |
| `scripts/nippo/create-cron.sh`     | なし | doc cron           |
| `scripts/nippo/draft-cron.sh`      | なし | doc cron           |
| `scripts/nippo/esa-weekly-cron.sh` | なし | doc skill cron     |

### セッション復元

| スクリプト                         | 引数                          | 呼び出し元 |
| ---------------------------------- | ----------------------------- | ---------- |
| `scripts/session/herdr-restore.sh` | `[--dry-run]` \| `[--status]` | doc fish   |
