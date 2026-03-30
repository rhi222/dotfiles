# CI エラーパターン集

## インフラ/AWS

### ECR RepositoryNotFoundException
```
RepositoryNotFoundException: The repository with name 'xxx' does not exist
```
- **原因**: ECRリポジトリ未作成、リージョン不一致、アカウントID違い
- **対処**: `aws ecr describe-repositories` で確認。CDKスタックでリポジトリ作成が先か確認

### ECS ClientException
```
ClientException: Deployment circuit breaker: tasks failed to start successfully
```
- **原因**: コンテナ起動失敗（環境変数不足、ポート設定、メモリ不足）
- **対処**: `aws ecs describe-tasks` でstoppedReason確認。CloudWatch Logsでコンテナログ確認

### CDK ChangeSet 作成失敗
```
No updates are to be performed / ChangeSet didn't contain changes
```
- **原因**: テンプレートに変更なし、前回のデプロイと同一
- **対処**: 通常は無害。CI側で `--require-approval never` と exit code ハンドリング確認

### CDK ROLLBACK_COMPLETE
```
Stack is in ROLLBACK_COMPLETE state and can not be updated
```
- **原因**: 前回のスタック作成/更新が失敗しロールバック完了状態
- **対処**: `aws cloudformation delete-stack` でスタック削除後に再デプロイ。手動リソースの有無を事前確認

### AssumeRole / OIDC 失敗
```
AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
```
- **原因**: OIDC信頼ポリシーの設定不備（リポジトリ名、ブランチ制限）
- **対処**: IAMロールの信頼ポリシーで `token.actions.githubusercontent.com` の条件を確認

## ビルド/依存関係

### Node.js バージョン警告
```
Node.js 16 actions are deprecated. Please update to Node.js 20.
```
- **原因**: 古いアクションバージョン使用
- **対処**: `actions/checkout@v4`, `actions/setup-node@v4` 等に更新

### pnpm install 失敗
```
ERR_PNPM_LOCKFILE_MISSING_DEPENDENCY
```
- **原因**: lockfileと package.json の不整合
- **対処**: ローカルで `pnpm install` して lockfile 更新・コミット

### TypeScript コンパイルエラー
```
error TS2345: Argument of type 'X' is not assignable to parameter of type 'Y'
```
- **原因**: 型不一致
- **対処**: エラー箇所の型定義を確認。`tsc --noEmit` でローカル再現

## デプロイ

### ECS ヘルスチェック失敗
```
service xxx has reached a steady state / essential container exited
```
- **原因**: アプリ起動失敗、ヘルスチェックパス不一致、起動時間超過
- **対処**: ヘルスチェック設定（パス、間隔、猶予期間）とアプリのログを確認

### DB マイグレーション失敗
```
Migration failed / relation "xxx" already exists
```
- **原因**: マイグレーションの重複適用、手動でのスキーマ変更
- **対処**: `prisma migrate status` でdrift確認。`prisma migrate resolve` で状態修正

## ワークフロー設定

### secrets 未設定
```
Error: Input required and not supplied: xxx
```
- **原因**: リポジトリ/環境のsecretsに値が未設定
- **対処**: Settings > Secrets and variables > Actions で該当secretを追加

### パーミッション不足
```
Resource not accessible by integration
```
- **原因**: GITHUB_TOKENの権限不足
- **対処**: ワークフローに `permissions:` ブロックを追加（`contents: read`, `id-token: write` 等）
