# Claude Code設定

## コミットメッセージ

`settings.json`で`includeCoAuthoredBy: false`に設定しているため、手動でコミットメッセージを作成する際は署名を含めないこと。

正しい例:

```bash
git commit -m "feat: 新機能を追加"
```

複数行の場合:

```bash
git commit -m "$(cat <<'EOF'
feat: 新機能を追加

詳細な説明
EOF
)"
```

Claude Codeの署名（`🤖 Generated with [Claude Code]`や`Co-Authored-By: Claude`）は含めない。
