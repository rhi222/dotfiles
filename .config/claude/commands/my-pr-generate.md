---
description: "Pull Request を自動生成するコマンド"
allowed-tools: Bash(gh:*),Bash(git rev-parse:*),Bash(git log:*),Bash(git diff:*),Bash(git remote show:*),Bash(awk:*),Bash(grep:*),Bash(glob:*)
---

現在のブランチの変更内容を分析し、適切なPull Requestを生成します。

## 使用方法

- 引数なし: 現在のブランチでPRを作成
- 引数あり: 指定されたブランチでPRを作成

## 実行手順

### 1. 対象ブランチの決定（引数未指定なら現在のブランチ）

- `git rev-parse --abbrev-ref HEAD`で現在のブランチ名を取得

### 2. ベースブランチの決定（デフォルトブランチを使用）

- `git remote show origin | grep 'HEAD branch' | awk '{print $NF}'`でデフォルトブランチを取得
- 異常終了条件: current branchがデフォルトブランチと同じ場合はエラー終了

### 3. 事前チェック

- `git log origin/$(git rev-parse --abbrev-ref HEAD)..HEAD`でcommit済み, push漏れを検知
- 異常終了条件: `git log origin/$(git rev-parse --abbrev-ref HEAD)..HEAD`の出力が空でない場合はエラー終了
- `git log <default_branch>..HEAD --oneline`でコミット存在を確認
- 異常終了条件: デフォルトブランチとの間にコミットがない場合はエラー終了

### 4. リポジトリルートの特定

- `git rev-parse --show-toplevel`でリポジトリルートを取得

### 5. PRテンプレートファイルの探索（Globツール使用）

- Globツールで `.github/PULL_REQUEST_TEMPLATE.md` と `.github/pull_request_template.md` を検索
- PRテンプレート優先順位
  - 1.  `repository_root/.github/PULL_REQUEST_TEMPLATE.md` (最優先)
  - 2.  `repository_root/.github/pull_request_template.md`
  - 3.  デフォルトテンプレート (概要、変更内容、テスト計画)

### 6. ベースブランチとの差分をgit diffとgit logで分析

- `git log <default_branch>..HEAD`でコミット履歴の確認
- `git diff <default_branch>...HEAD`でデフォルトブランチとの差分分析
- 変更されたファイルの種類と目的の特定
- テストやドキュメントの更新状況

### 7. コミットメッセージとコード変更の内容から意図を理解

### 8. 適切なPRタイトルと説明文を生成

### 9. `gh pr create`を使用してPRを作成

- `gh pr create --base <default_branch> --head <current_branch> --title "..." --body "..."`
  - default_branch: 手順2で取得したブランチをbaseブランチとして明示してください
  - current_branch: 手順1で取得したブランチをheadブランチとして明示してください

- コマンド実行前にuserに確認をもとめること
