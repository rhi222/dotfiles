# Claude Code設定

## 基本ルール

- 思考は英語、回答の生成は日本語で行う

## コミットメッセージ

`settings.json`で`includeCoAuthoredBy: false`に設定しているため、手動でコミットメッセージを作成する際は署名を含めないこと。

正しい例:

```fish
git commit -m "feat: 新機能を追加"
```

複数行の場合:

```fish
git commit -m "feat: 新機能を追加

詳細な説明"
```

Claude Codeの署名（`🤖 Generated with [Claude Code]`や`Co-Authored-By: Claude`）は含めない。

## コミットの分割

変更意図が追いかけやすいように、コミットは適切な粒度に分割する。

### 原則

- **1コミット＝1つの論理的変更**にする。「あとから `git log` や `git blame` を見た人が、なぜこの変更をしたか1コミットで理解できる」を基準にする。
- 種類の異なる変更（`feat` / `fix` / `refactor` / `docs` / `chore` など）は別コミットに分ける。
- **リファクタリングと機能追加・修正は必ず分ける**。「動作を変えない整理」と「動作を変える実装」を混ぜない。
- フォーマット・リネームのみの機械的変更は、ロジック変更と分けて単独コミットにする（差分レビューのノイズを減らすため）。
- 各コミットは**それ単体でビルド・テストが通る**状態にする（`git bisect` を壊さない）。

### 判断基準

以下に当てはまる場合は分割を検討する。

- コミットメッセージに「〜と〜」「ついでに」「あわせて」を書きたくなったとき
- 1つの type（`feat` など）に複数の独立した関心事が含まれるとき
- 複数ファイルの変更でも、目的が別々のとき

逆に、密結合で片方だけコミットすると壊れる変更（実装とその型定義など）は無理に分けず1コミットにまとめる。

### 手順

- 変更が混在してしまった場合は `git add -p`（ハンク単位）や `git add <path>` で関連する差分だけをステージしてからコミットする。
- コミット前に `git diff --staged` でステージ内容が単一の意図に閉じているか確認する。

## コミットしないもの

- `docs/superpowers/`（superpowersのspec/planドキュメント）はコミットしない。`.gitignore` で管理対象外にしているため、`git add -A` などで誤って追加しないこと。

## shellコマンド

- ユーザーへの回答でコマンド例を示す際はfish構文で記述すること（開発者のログインシェルがfishのため）
- Claude Code自身がBashツールで実行するコマンドはPOSIX/Bash構文のままでよい

## 開発ルール

開発スタイル系のルールは `rules/` 配下に分離し、以下を import する。
`obsidian-vault.md` と `deck.md` は path-scope が狭いため、必要に応じて該当ディレクトリの CLAUDE.md から個別参照する想定。

@rules/tdd.md
@rules/refactoring.md
@rules/review-mode.md
@rules/investigation-mode.md
