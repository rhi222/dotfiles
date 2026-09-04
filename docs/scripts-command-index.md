# scripts/の公開コマンド索引

[scripts-layout.md](scripts-layout.md) から分割した、公開スクリプトと呼び出し元の一覧。
リポジトリ内では以下の正規pathを使う。旧 `~/scripts/<name>` は [`scripts/compat-links.txt`](../scripts/compat-links.txt) が維持する。
引数は各スクリプト冒頭の使用法を正とし、ここでは重複管理しない。

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

| スクリプト                              | 呼び出し元       |
| --------------------------------------- | ---------------- |
| `scripts/repository/lint.sh`            | doc hook fish ci |
| `scripts/repository/markdown-format.sh` | doc hook ci      |
| `scripts/repository/secret-scan.sh`     | doc hook ci link |
| `scripts/repository/doc-budget.sh`      | doc hook ci      |
| `scripts/repository/ref-check.sh`       | hook ci          |
| `scripts/repository/run-tests.sh`       | doc ci           |
| `scripts/doctor/migration.sh`           | doc              |
| `scripts/doctor/residue.sh`             | doc              |

### セットアップ（新環境の立ち上げ）

| スクリプト                       | 呼び出し元 |
| -------------------------------- | ---------- |
| `scripts/setup/bootstrap.sh`     | doc        |
| `scripts/setup/agent-plugins.sh` | doc        |
| `scripts/setup/apt.sh`           | doc boot   |
| `scripts/setup/dotctl.sh`        | doc boot   |
| `scripts/setup/claude-skills.sh` | doc        |
| `scripts/setup/fish-plugins.sh`  | doc        |
| `scripts/setup/gh-extensions.sh` | doc        |
| `scripts/setup/yazi-plugins.sh`  | doc boot   |
| `scripts/linear/bootstrap.sh`    | doc link   |

### 同期・運搬

| スクリプト                           | 呼び出し元 |
| ------------------------------------ | ---------- |
| `scripts/settings/sync-claude.sh`    | doc boot   |
| `scripts/settings/sync-codex.sh`     | doc        |
| `scripts/settings/sync-windows.sh`   | doc        |
| `scripts/settings/private-bundle.sh` | doc link   |

### 更新

| スクリプト                | 呼び出し元 |
| ------------------------- | ---------- |
| `scripts/update/daily.sh` | doc hook   |

### skill 管理

| スクリプト                 | 呼び出し元 |
| -------------------------- | ---------- |
| `scripts/skills/add.sh`    | doc        |
| `scripts/skills/audit.sh`  | doc        |
| `scripts/skills/vendor.sh` | doc        |

### agent plugin管理

| スクリプト                  | 呼び出し元 |
| --------------------------- | ---------- |
| `scripts/plugins/vendor.sh` | doc        |

### worktree

| スクリプト                    | 呼び出し元          |
| ----------------------------- | ------------------- |
| `scripts/worktree/init.sh`    | doc skill hook link |
| `scripts/worktree/cleanup.sh` | doc skill           |

### git

| スクリプト                 | 呼び出し元 |
| -------------------------- | ---------- |
| `scripts/git/check-tag.sh` | doc        |

### db

| スクリプト             | 呼び出し元 |
| ---------------------- | ---------- |
| `scripts/db/tunnel.sh` | doc        |

### 掃除

| スクリプト               | 呼び出し元 |
| ------------------------ | ---------- |
| `scripts/wsl/cleanup.sh` | doc        |

### Linear

| スクリプト                           | 呼び出し元          |
| ------------------------------------ | ------------------- |
| `scripts/linear/sweep.sh`            | doc skill fish link |
| `scripts/linear/slack-sweep.sh`      | doc skill           |
| `scripts/linear/slack-sweep-cron.sh` | doc cron            |
| `scripts/linear/interview-prep.sh`   | doc skill cron      |
| `scripts/linear/dispatch-cron.sh`    | doc skill link cron |
| `scripts/linear/em-dispatch.sh`      | doc skill           |

### 日報・レポート

| スクリプト                         | 呼び出し元         |
| ---------------------------------- | ------------------ |
| `scripts/nippo/check.sh`           | doc hook link cron |
| `scripts/nippo/notify-cron.sh`     | doc link cron      |
| `scripts/nippo/create-cron.sh`     | doc cron           |
| `scripts/nippo/draft-cron.sh`      | doc cron           |
| `scripts/nippo/esa-weekly-cron.sh` | doc skill cron     |
| `scripts/esa/sos-precheck.sh`      | skill              |

### セッション復元

| スクリプト                         | 呼び出し元 |
| ---------------------------------- | ---------- |
| `scripts/session/herdr-restore.sh` | doc fish   |
