# scripts/の公開コマンド索引

[scripts-layout.md](scripts-layout.md) から分割した、公開スクリプトの引数と呼び出し元の一覧。

## 公開入口の一覧

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
| `boot`  | `scripts/bootstrap.sh`                          |
| `cron`  | crontab 行（`*-cron.sh` 自身を含む）            |

### 検査

| スクリプト           | 引数                  | 呼び出し元       |
| -------------------- | --------------------- | ---------------- |
| `lint.sh`            | `[--fix]`             | doc hook fish ci |
| `secret-scan.sh`     | `--staged` / `--tree` | doc hook ci link |
| `doc-budget.sh`      | `[--staged]`          | doc hook ci      |
| `ref-check.sh`       | なし                  | hook ci          |
| `run-tests.sh`       | `[--ci]`              | doc ci           |
| `migration-check.sh` | `[<dir>...]`          | doc              |
| `env-residue.sh`     | なし                  | doc              |

### セットアップ（新環境の立ち上げ）

| スクリプト               | 引数          | 呼び出し元 |
| ------------------------ | ------------- | ---------- |
| `bootstrap.sh`           | なし          | doc        |
| `apt-setup.sh`           | なし          | doc boot   |
| `setup-dotctl.sh`        | なし          | doc boot   |
| `setup-claude-skills.sh` | `[--dry-run]` | doc        |
| `setup-fish-plugins.sh`  | `[--dry-run]` | doc        |
| `setup-gh-extensions.sh` | `[--dry-run]` | doc        |
| `setup-yazi-plugins.sh`  | `[--dry-run]` | doc boot   |
| `linear-bootstrap.sh`    | なし          | doc link   |

### 同期・運搬

| スクリプト                 | 引数                                                    | 呼び出し元 |
| -------------------------- | ------------------------------------------------------- | ---------- |
| `sync-claude-settings.sh`  | `status`\|`pull`\|`push [--force]`                      | doc boot   |
| `sync-windows-settings.sh` | `status`\|`pull`\|`push` `[target]`                     | doc        |
| `private-bundle.sh`        | `adopt [--execute]`\|`export`\|`import <zip>`\|`status` | doc link   |

### 更新

| スクリプト        | 引数 | 呼び出し元 |
| ----------------- | ---- | ---------- |
| `daily-update.sh` | なし | doc hook   |

### skill 管理

| スクリプト        | 引数                                                       | 呼び出し元 |
| ----------------- | ---------------------------------------------------------- | ---------- |
| `skill-add.sh`    | `<owner/repo> <skill>`                                     | doc        |
| `skill-audit.sh`  | `[--quiet] <skill-dir>`                                    | doc        |
| `skill-vendor.sh` | `add <repo> <sub-path> [name]`\|`update <name> [name...]`\|`status`\|`list` | doc        |

### worktree

| スクリプト            | 引数                             | 呼び出し元          |
| --------------------- | -------------------------------- | ------------------- |
| `worktree-init.sh`    | `[--dry-run] [<path>]`           | doc skill hook link |
| `worktree-cleanup.sh` | `[--size] [--execute] [--force]` | doc skill           |

### 掃除

| スクリプト       | 引数          | 呼び出し元 |
| ---------------- | ------------- | ---------- |
| `wsl-cleanup.sh` | `[--execute]` | doc        |

### Linear

| スクリプト                   | 引数             | 呼び出し元          |
| ---------------------------- | ---------------- | ------------------- |
| `linear-sweep.sh`            | なし             | doc skill fish link |
| `linear-slack-sweep.sh`      | `[unseen <key>]` | doc skill           |
| `linear-slack-sweep-cron.sh` | なし             | doc cron            |
| `linear-interview-prep.sh`   | `[unseen <id>]`  | doc skill cron      |
| `linear-dispatch-cron.sh`    | なし             | doc skill link cron |

### 日報・レポート

| スクリプト             | 引数 | 呼び出し元         |
| ---------------------- | ---- | ------------------ |
| `nippo-check.sh`       | なし | doc hook link cron |
| `nippo-cron.sh`        | なし | doc link cron      |
| `nippo-create-cron.sh` | なし | doc cron           |
| `nippo-draft-cron.sh`  | なし | doc cron           |
| `esa-weekly-cron.sh`   | なし | doc skill cron     |

### セッション復元

| スクリプト         | 引数                          | 呼び出し元 |
| ------------------ | ----------------------------- | ---------- |
| `herdr-restore.sh` | `[--dry-run]` \| `[--status]` | doc fish   |
