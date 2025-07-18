# PR生成コマンド

現在のブランチの変更内容を分析し、適切なPull Requestを生成します。

## 使用方法

- 引数なし: 現在のブランチでPRを作成
- 引数あり: 指定されたブランチでPRを作成

## 実行手順

1. 対象ブランチの決定（引数未指定なら現在のブランチ）
2. ベースブランチの決定（デフォルトブランチを使用）

- `git remote show origin | grep 'HEAD branch' | awk '{print $NF}'`でデフォルトブランチを取得

3. リモートブランチとの同期確認（push漏れをチェック）
4. リポジトリルートの特定

- `git rev-parse --show-toplevel`でリポジトリルートを取得

5. PRテンプレートファイルの探索（Globツール使用）
6. ベースブランチとの差分をgit diffとgit logで分析
7. コミットメッセージとコード変更の内容から意図を理解
8. 適切なPRタイトルと説明文を生成
9. `gh pr create`を使用してPRを作成（ベースブランチ指定、pushは自動実行）

## 分析内容

- `git log <base_branch>..HEAD`でコミット履歴の確認
- `git diff <base_branch>...HEAD`でベースブランチとの差分分析
- 変更されたファイルの種類と目的の特定
- テストやドキュメントの更新状況
- リポジトリのPRテンプレート確認

## PRテンプレート優先順位

1. `repository_root/.github/PULL_REQUEST_TEMPLATE.md` (最優先)
2. `repository_root/.github/pull_request_template.md`
3. デフォルトテンプレート (概要、変更内容、テスト計画)

実装時の探索方法:

- `git rev-parse --show-toplevel`でリポジトリルートを取得
- `git remote show origin | grep 'HEAD branch' | awk '{print $NF}'`でデフォルトブランチを取得
- `git status --porcelain`でuncommitted changesをチェック
- `git log @{u}..HEAD`でunpushed commitsをチェック（異常終了条件）
- Globツールで `.github/PULL_REQUEST_TEMPLATE.md` と `.github/pull_request_template.md` を検索
- テンプレートが存在しない場合はデフォルトテンプレートを使用
- `gh pr create`は自動でpushを実行するため、事前のgit pushは不要

従来のコミット形式（feat, fix, docs等）に基づいてPRタイトルを生成します。
