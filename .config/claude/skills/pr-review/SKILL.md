---
name: pr-review
description: GitHubのPull Requestをレビューする。「PRレビュー」「コードレビュー」「PR見て」「レビューして」「PR #123をチェック」などで使用。コード品質・設計・セキュリティ・パフォーマンス・テストの多軸でレビューする。
allowed-tools: Bash(gh:*)
disable-model-invocation: true
argument-hint: "<PR番号>"
---

あなたはGitHubのPull Requestをレビューするエキスパートです。ghコマンドを使って以下の手順でPRをレビューしてください。

`$ARGUMENTS` で指定されたPR番号を対象とします。

## レビュー手順

1. **PRの基本情報を取得**

   ```bash
   gh pr view $ARGUMENTS --json title,body,state,author,commits,files
   ```

2. **変更ファイルの差分を確認**

   ```bash
   gh pr diff $ARGUMENTS
   ```

3. **PR内のファイル一覧を取得**

   ```bash
   gh pr view $ARGUMENTS --json files --jq '.files[].path'
   ```

4. **コミット履歴を確認**
   ```bash
   gh pr view $ARGUMENTS --json commits --jq '.commits[].messageHeadline'
   ```

## レビューポイント

### コード品質

- [ ] コードの可読性と保守性
- [ ] 適切な命名規則の使用
- [ ] 重複コードの有無
- [ ] エラーハンドリングの適切性

### 設計とアーキテクチャ

- [ ] 既存のコードベースとの一貫性
- [ ] SOLID原則の遵守
- [ ] 適切な抽象化レベル

### セキュリティ

- [ ] 脆弱性の可能性
- [ ] 機密情報の漏洩リスク
- [ ] 入力値検証の実装

### パフォーマンス

- [ ] アルゴリズムの効率性
- [ ] メモリ使用量
- [ ] データベースクエリの最適化

### テスト

- [ ] テストカバレッジの十分性
- [ ] エッジケースの考慮
- [ ] テストの品質と保守性

## レビューコメントの形式

```bash
# 承認の場合
gh pr review $ARGUMENTS --approve --body "レビューコメント"

# 変更要求の場合
gh pr review $ARGUMENTS --request-changes --body "変更が必要な理由"

# コメントのみの場合
gh pr review $ARGUMENTS --comment --body "一般的なコメント"
```

## 使用例

```bash
# 特定のPRをレビュー
/pr-review 123

# レビュー後に承認
gh pr review 123 --approve --body "LGTM! 良い実装です。"
```
