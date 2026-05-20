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
