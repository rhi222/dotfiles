---
name: pr-auto-update
description: Pull Requestの説明とラベルを自動更新する
allowed-tools: Bash(gh:*)
disable-model-invocation: true
argument-hint: "[--pr <番号>] [--description-only] [--labels-only] [--dry-run]"
---

## 概要

Pull Request の説明とラベルを自動的に更新するスキルです。Git の変更内容を分析して、適切な説明文とラベルを生成・設定します。

## 使い方

```bash
/pr-auto-update [オプション] [PR 番号]
```

### オプション (`$ARGUMENTS` で指定)

- `--pr <番号>` : 対象の PR 番号を指定（省略時は現在のブランチから自動検出）
- `--description-only` : 説明文のみ更新（ラベルは変更しない）
- `--labels-only` : ラベルのみ更新（説明文は変更しない）
- `--dry-run` : 実際の更新は行わず、生成される内容のみ表示
- `--lang <言語>` : 言語を指定（ja, en）

### 基本例

```bash
# 現在のブランチの PR を自動更新
/pr-auto-update

# 特定の PR を更新
/pr-auto-update --pr 1234

# 説明文のみ更新
/pr-auto-update --description-only

# ドライランで確認
/pr-auto-update --dry-run
```

## 機能詳細

### 1. PR の自動検出

現在のブランチから対応する PR を自動検出：

```bash
# ブランチから PR を検索
gh pr list --head $(git branch --show-current) --json number,title,url
```

### 2. 変更内容の分析

以下の情報を収集・分析：

- **ファイル変更**: 追加・削除・変更されたファイル
- **コード分析**: import 文、関数定義、クラス定義の変更
- **テスト**: テストファイルの有無と内容
- **ドキュメント**: README、docs の更新
- **設定**: package.json、pubspec.yaml、設定ファイルの変更
- **CI/CD**: GitHub Actions、workflow の変更

### 3. 説明文の自動生成

#### テンプレート処理の優先順位

1. **既存の PR 説明**: 既に記述されている内容を**完全に踏襲**
2. **プロジェクトテンプレート**: `.github/PULL_REQUEST_TEMPLATE.md` から構造を取得
3. **デフォルトテンプレート**: 上記が存在しない場合のフォールバック

#### 既存内容の保持ルール

**重要**: 既存の内容は変更しない

- 書かれているセクションは保持
- 空のセクションのみ補完
- 機能的なコメント（Copilot review rule など）は保持

#### プロジェクトテンプレートの使用

```bash
# .github/PULL_REQUEST_TEMPLATE.md の構造を解析
parse_template_structure() {
  local template_file="$1"

  if [ -f "$template_file" ]; then
    # セクション構造を抽出
    grep -E '^##|^###' "$template_file"

    # コメントプレースホルダーを特定
    grep -E '<!--.*-->' "$template_file"

    # 既存のテンプレート構造を完全に踏襲
    cat "$template_file"
  fi
}
```

### 4. ラベルの自動設定

#### ラベル取得の仕組み

**優先順位**:

1. **`.github/labels.yml`**: プロジェクト固有のラベル定義から取得
2. **GitHub API**: `gh api repos/{OWNER}/{REPO}/labels --jq '.[].name'` で既存ラベルを取得

#### 自動判定ルール

**ファイルパターンベース**:

- ドキュメント: `*.md`, `README`, `docs/` → `documentation|docs|doc` を含むラベル
- テスト: `test`, `spec` → `test|testing` を含むラベル
- CI/CD: `.github/`, `*.yml`, `Dockerfile` → `ci|build|infra|ops` を含むラベル
- 依存関係: `package.json`, `pubspec.yaml`, `requirements.txt` → `dependencies|deps` を含むラベル

**変更内容ベース**:

- バグ修正: `fix|bug|error|crash|修正` → `bug|fix` を含むラベル
- 新機能: `feat|feature|add|implement|新機能|実装` → `feature|enhancement|feat` を含むラベル
- リファクタリング: `refactor|clean|リファクタ` → `refactor|cleanup|clean` を含むラベル
- パフォーマンス: `performance|perf|optimize|パフォーマンス` → `performance|perf` を含むラベル
- セキュリティ: `security|secure|セキュリティ` → `security` を含むラベル

#### 制約

- **最大 3 個まで**: 自動選択されるラベル数の上限
- **既存ラベルのみ**: 新しいラベルの作成は禁止
- **部分マッチ**: ラベル名にキーワードが含まれているかで判定

### 5. 実行フロー

```bash
#!/bin/bash

# 1. PR の検出・取得
detect_pr() {
  if [ -n "$PR_NUMBER" ]; then
    echo $PR_NUMBER
  else
    gh pr list --head $(git branch --show-current) --json number --jq '.[0].number'
  fi
}

# 2. 変更内容の分析
analyze_changes() {
  local pr_number=$1
  gh pr diff $pr_number --name-only
  gh pr diff $pr_number | head -1000
}

# 3. 説明文の生成
generate_description() {
  local pr_number=$1
  local current_body=$(gh pr view $pr_number --json body --jq -r .body)

  if [ -n "$current_body" ]; then
    echo "$current_body"
  else
    local template_file=".github/PULL_REQUEST_TEMPLATE.md"
    if [ -f "$template_file" ]; then
      generate_from_template "$(cat "$template_file")" "$changes"
    else
      generate_from_template "" "$changes"
    fi
  fi
}

# 4. ラベルの決定
determine_labels() {
  local changes=$1 file_list=$2 pr_number=$3

  # 利用可能なラベルを取得
  if [ -f ".github/labels.yml" ]; then
    grep "^- name:" .github/labels.yml | sed "s/^- name: '\?\([^']*\)'\?/\1/"
  else
    local repo_info=$(gh repo view --json owner,name)
    local owner=$(echo "$repo_info" | jq -r .owner.login)
    local repo=$(echo "$repo_info" | jq -r .name)
    gh api "repos/$owner/$repo/labels" --jq '.[].name'
  fi
  # 最大 3 個に制限
}

# 5. PR の更新
update_pr() {
  local pr_number=$1 description="$2" labels="$3"

  if [ "$DRY_RUN" = "true" ]; then
    echo "=== DRY RUN ==="
    echo "Description:" && echo "$description"
    echo "Labels: $labels"
  else
    local repo_info=$(gh repo view --json owner,name)
    local owner=$(echo "$repo_info" | jq -r .owner.login)
    local repo=$(echo "$repo_info" | jq -r .name)

    gh api --method PATCH "/repos/$owner/$repo/pulls/$pr_number" \
      --field body="$description"

    if [ -n "$labels" ]; then
      gh pr edit $pr_number --add-label "$labels"
    fi
  fi
}
```

## プロジェクト別テンプレート例

プロジェクトの種類に応じた説明文テンプレートは以下のサポートファイルを参照：

- `examples/flutter-template.md` - Flutterプロジェクト向け
- `examples/nodejs-template.md` - Node.jsプロジェクト向け
- `examples/cicd-template.md` - CI/CD改善向け

## 注意事項

1. **既存内容の完全保持**:
   - 既に記述されている内容は**一文字も変更しない**
   - 空のコメント部分とプレースホルダーのみ補完
   - ユーザーが意図的に書いた内容を尊重

2. **テンプレート優先順位**:
   - 既存の PR 説明 > `.github/PULL_REQUEST_TEMPLATE.md` > デフォルト
   - プロジェクト固有のテンプレート構造を完全踏襲

3. **ラベル制約**:
   - `.github/labels.yml` が存在すれば優先使用
   - 存在しない場合は GitHub API から既存ラベルを取得
   - 新しいラベルの作成は禁止
   - 最大 3 個まで自動選択

4. **安全な更新**:
   - `--dry-run` で事前確認を推奨
   - 機密情報を含む変更の場合は警告表示

5. **GitHub CLI の HTML コメントエスケープ問題**:
   - GitHub API の `--field` オプションを使用して適切なエスケープ処理
   - シェル処理の簡素化で混入を防止

## トラブルシューティング

1. **PR が見つからない**: ブランチ名と PR の関連付けを確認
2. **権限エラー**: GitHub CLI の認証状態を確認
3. **ラベルが設定できない**: リポジトリの権限を確認
4. **HTML コメントがエスケープされる**: `--field` オプションで回避
