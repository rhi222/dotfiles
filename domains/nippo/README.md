# Nippo domain

日報の作成、状態確認、通知、ドラフト仕上げ、週次レポート生成をこのディレクトリに
集約する。

- `scripts/`: cronと状態チェックの実装
- `lib/paths.sh`: Vault、日報、週報のパスを解決するShell API
- `../../tests/nippo/`: ドメインの回帰テスト
- `../../docs/nippo-automation.md`: cron、dry-run、allowed toolsの仕様

外部からの公開入口は従来どおり `scripts/nippo-*.sh` と
`scripts/esa-weekly-cron.sh`、公開Shell APIは `scripts/lib/nippo-paths.sh` とする。
cron、skill、hook、文書から `domains/` の実装パスを直接呼ばない。

依存方向は `公開入口 -> domains/nippo -> scripts/libの共通基盤`。パスは必ず
`lib/paths.sh`に集約し、scriptやskillでVaultの内部構造を組み立てない。
