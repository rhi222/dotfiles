# Nippo domain

日報の作成、状態確認、通知、ドラフト仕上げ、週次レポート生成をこのディレクトリに
集約する。

- `scripts/`: cronと状態チェックの実装
- `lib/paths.sh`: Vault、日報、週報のパスを解決するShell API
- `../../tests/nippo/`: ドメインの回帰テスト
- `../../docs/nippo-automation.md`: cron、dry-run、allowed toolsの仕様

正規の公開入口は `scripts/nippo/*.sh`、旧 `~/scripts/nippo-*.sh` は互換link、
`scripts/nippo/esa-weekly-cron.sh`、公開Shell APIは `scripts/lib/nippo-paths.sh` とする。
cron、skill、hook、文書から `internal/` の実装パスを直接呼ばない。

依存方向は `scriptsの公開入口 -> internal/nippo -> internalの共有基盤`。パスは必ず
`lib/paths.sh`に集約し、scriptやskillでVaultの内部構造を組み立てない。
