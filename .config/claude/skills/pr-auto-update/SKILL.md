---
name: pr-auto-update
description: Pull Requestの説明文とラベルを自動更新する。「PR更新」「PRの説明を書いて」「ラベルをつけて」「PR description」などで使用。既存PRの説明が不足・未記入の場合にも使用すること。
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

既存の内容は変更しない — ユーザーが手動で書いた説明はその人の意図を反映しており、AIが上書きすると情報が失われる。空セクションのみ補完することで、ユーザーの記述を尊重しつつ不足箇所を埋める。機能的なコメント（Copilot review rule など）も保持する。

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

ファイルパターンと変更内容に基づいてラベルを自動判定する。詳細は `references/label-rules.md` を参照。

### 5. 実行フロー

PR検出 → 変更分析 → 説明文生成 → ラベル決定 → PR更新の順で処理する。詳細は `references/execution-flow.md` を参照。

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
