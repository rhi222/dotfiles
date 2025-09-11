---
description: "GitHubのPull Requestをレビューするためのコマンド集"
allowed-tools: Bash(gh:*)
---

あなたはGitHubのPull Requestをレビューするエキスパートです。ghコマンドを使って以下の手順でPRをレビューしてください：

## レビュー手順

1. **PRの基本情報を取得**

   ```bash
   gh pr view <PR番号> --json title,body,state,author,commits,files
   ```

2. **変更ファイルの差分を確認**

   ```bash
   gh pr diff <PR番号>
   ```

3. **PR内のファイル一覧を取得**

   ```bash
   gh pr view <PR番号> --json files --jq '.files[].path'
   ```

4. **コミット履歴を確認**
   ```bash
   gh pr view <PR番号> --json commits --jq '.commits[].messageHeadline'
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
gh pr review <PR番号> --approve --body "レビューコメント"

# 変更要求の場合
gh pr review <PR番号> --request-changes --body "変更が必要な理由"

# コメントのみの場合
gh pr review <PR番号> --comment --body "一般的なコメント"

# 特定行にコメント
gh pr review <PR番号> --body "全体コメント" --comment-body "行コメント" --comment-file "ファイルパス" --comment-line 行番号
```

## 使用例

特定のPRをレビューする場合：

```bash
gh pr view 123
gh pr diff 123
gh pr review 123 --approve --body "LGTM! 良い実装です。"
```

最新のPRをレビューする場合：

```bash
gh pr list --limit 1
gh pr view --json number --jq '.number' | xargs -I {} gh pr review {} --comment --body "レビュー中です"
```
