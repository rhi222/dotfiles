# Linear domain

Linearを個人タスクの司令塔として使う機能を、このディレクトリに集約する。

- `scripts/`: bootstrap、sweep、dispatchなどの実装
- `lib/api.sh`: GraphQLと設定を扱うShell API
- `../../tests/linear/`: ドメインの回帰テスト
- `../../docs/linear-command-layer.md`: 状態、Cycle、dispatchの仕様

外部からの公開入口は従来どおり `scripts/linear-*.sh`、公開Shell APIは
`scripts/lib/linear-api.sh` とする。どちらも互換層なので、cron、skill、hook、文書から
`internal/` の実装パスを直接呼ばない。

依存方向は `scriptsの公開入口 -> internal/linear -> internalの共有基盤`。LinearからSlack、
GitHub、Jira、esaへ書き戻さず、外部へのpointerだけを保持する。
