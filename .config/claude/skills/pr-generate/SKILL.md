---
name: pr-generate
description: Pull Requestを自動生成する。「PR作成」「プルリク」「pull request」「PRを出して」「PRを作って」などで使用。差分・コミット分析からタイトル・説明文を自動生成し、gh pr createで作成する。
allowed-tools: Bash(gh:*),Bash(git rev-parse:*),Bash(git log:*),Bash(git diff:*),Bash(git remote show:*)
disable-model-invocation: true
argument-hint: "[base-branch]"
---

現在のブランチの変更内容を分析し、適切なPull Requestを生成します。

**PR作成方針は `~/.claude/rules/pull-request.md` に従う。** 分割が必要な規模になったら、
ブランチを手で切って `gh pr create --base <下のブランチ>` を組み立てるのではなく、
**必ず `gh stack`（`gh-stack` 拡張）を使う**。手組みは base の付け替え・rebase・マージ後の
同期を全部手作業で背負うことになり、実際に事故になっている。

## 使用方法

- 引数なし: デフォルトブランチをベースにPRを作成
- 引数あり (`$ARGUMENTS`): 指定されたブランチをベースブランチとして使用

## 実行手順

### 1. 対象ブランチの決定

- `git rev-parse --abbrev-ref HEAD`で現在のブランチ名を取得

### 2. ベースブランチの決定

- `$ARGUMENTS` が指定されている場合: その値をベースブランチとして使用
- `$ARGUMENTS` が未指定の場合: `git remote show origin | grep 'HEAD branch' | awk '{print $NF}'`でデフォルトブランチを取得
- 異常終了条件: current branchがベースブランチと同じ場合はエラー終了

### 3. 事前チェック

- `git log origin/$(git rev-parse --abbrev-ref HEAD)..HEAD`でcommit済み, push漏れを検知
- 異常終了条件: `git log origin/$(git rev-parse --abbrev-ref HEAD)..HEAD`の出力が空でない場合はエラー終了
- `git log <base_branch>..HEAD --oneline`でコミット存在を確認
- 異常終了条件: ベースブランチとの間にコミットがない場合はエラー終了

### 4. リポジトリルートの特定

- `git rev-parse --show-toplevel`でリポジトリルートを取得

### 5. PRテンプレートファイルの探索（Globツール使用）

- Globツールで `.github/PULL_REQUEST_TEMPLATE.md` と `.github/pull_request_template.md` を検索
- PRテンプレート優先順位
  - 1.  `repository_root/.github/PULL_REQUEST_TEMPLATE.md` (最優先)
  - 2.  `repository_root/.github/pull_request_template.md`
  - 3.  デフォルトテンプレート (概要、変更内容、テスト計画)

### 6. ベースブランチとの差分をgit diffとgit logで分析

- `git log <base_branch>..HEAD`でコミット履歴の確認
- `git diff <base_branch>...HEAD`でベースブランチとの差分分析
- 変更されたファイルの種類と目的の特定
- テストやドキュメントの更新状況

### 7. コミットメッセージとコード変更の内容から意図を理解

### 8. スタック分割の要否を判定する

- `git diff <base_branch>...HEAD --shortstat` で変更行数を見る（lockファイル等の自動生成分は数えない）
- 次のいずれかに当たったらスタック分割を提案し、userに判断を仰ぐ
  - 変更が **±400行程度**を超える
  - PRの目的が1文で説明できず、「〜と〜」が必要になる
  - レビュー観点が変わる切れ目がある（準備リファクタ → 本体実装、型定義 → 実装 → 呼び出し側の移行、機械的な一括変更 → ロジック変更）
- 目安以下に収まるなら単発PRでよい。スタックを強制しない

### 9. 適切なPRタイトルと説明文を生成

### 10. PRを作成

コマンド実行前にuserに確認をもとめること。

#### 単発PRの場合

- `gh pr create --base <base_branch> --head <current_branch> --title "..." --body "..."`
  - base_branch: 手順2で決定したブランチをbaseブランチとして明示してください
  - current_branch: 手順1で取得したブランチをheadブランチとして明示してください

#### スタック分割する場合

- **`gh pr create` を自分で組み立てない。`gh stack` を使う。** スタックの作成・push・rebase・
  マージ後の同期はすべて `gh-stack` 拡張の担当
- 使い方が不確かなら `gh-stack` skill を参照する
- `gh pr create --base <デフォルトブランチ以外>` を打とうとすると `pr-base-guard` hook が
  割り込む。これはスタックを手組みしかけている合図なので、素通ししようとせず `gh stack` に戻る
