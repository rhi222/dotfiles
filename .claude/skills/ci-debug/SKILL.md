---
name: ci-debug
description: GitHub Actionsのエラーログを分析し、原因分類と対処法を提示する。「CIが落ちた」「GitHub Actionsのエラー」「デプロイ失敗」「ワークフローが失敗」等で使用。ユーザーがGH Actionsのログやエラーメッセージを貼り付けた場合にも自動トリガー。
---

# CI Debug スキル

GitHub Actions のエラーログから原因を特定し、対処法を提示する。

## トリガー条件

- ユーザーが GH Actions のエラーログを貼り付けた
- 「CIが落ちた」「デプロイ失敗」「ワークフローのエラー」等のキーワード
- GH Actions の URL（`github.com/*/actions/runs/*`）が共有された

## 処理フロー

1. **エラーログの取得**: ユーザーが貼り付けたログ、または GH Actions URL から `gh run view` / `gh api` でログを取得
2. **構造化分類**: `error-patterns.md` のパターンに照合し、エラーを分類
3. **原因特定**: エラー種別ごとの典型的原因を提示
4. **対処法提示**: 具体的な修正手順を提案（コード変更、設定変更、リトライ等）
5. **再発防止**: 必要に応じてワークフローの改善提案

## ログ取得コマンド

```bash
# 失敗したrunのログ取得
gh run view <run-id> --log-failed

# 特定ジョブのログ
gh run view <run-id> --job <job-id> --log

# 直近の失敗run一覧
gh run list --status failure --limit 5
```

## エラー分類フレームワーク

エラーを以下の5カテゴリに分類して報告する:

### 1. インフラ/AWS エラー
- **ECR**: RepositoryNotFoundException, AuthorizationException
- **ECS**: ClientException, service不安定, タスク起動失敗
- **CDK**: ChangeSet作成失敗, スタックdrift, ROLLBACK_COMPLETE
- **IAM**: AccessDenied, AssumeRole失敗, OIDC設定不備

### 2. ビルド/依存関係エラー
- **Node.js**: バージョン非推奨警告, エンジン不一致
- **パッケージ**: npm/pnpm install失敗, lockfile不整合
- **TypeScript**: 型エラー, コンパイル失敗
- **Docker**: ビルド失敗, マルチステージ問題

### 3. テスト失敗
- **ユニットテスト**: assertion失敗, タイムアウト
- **E2Eテスト**: セレクタ変更, 環境依存
- **Lint/Format**: ESLint, Prettier違反

### 4. デプロイ/リリースエラー
- **CDK deploy**: スタック更新失敗, リソース競合
- **ECS deploy**: ヘルスチェック失敗, ローリング更新タイムアウト
- **DB migration**: マイグレーション失敗, スキーマ不整合

### 5. ワークフロー設定エラー
- **権限**: GITHUB_TOKEN不足, secrets未設定
- **構文**: YAML構文エラー, expression評価失敗
- **トリガー**: イベント不一致, パスフィルタ問題

## 出力フォーマット

```markdown
## CI エラー分析

**ワークフロー**: [ワークフロー名]
**ジョブ/ステップ**: [失敗箇所]
**カテゴリ**: [上記5分類のいずれか]

### エラー内容
[エラーメッセージの要約]

### 原因
[特定された原因]

### 対処法
1. [具体的な修正手順]

### 補足
[再発防止策や関連情報があれば]
```

## よくあるパターンと即時対処

エラーパターンの詳細と対処法は `error-patterns.md` を参照。
