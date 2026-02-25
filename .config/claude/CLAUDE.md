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

## Test-Driven Development (TDD)

- 原則としてテスト駆動開発（TDD）で進める

- 期待される入出力に基づき、まずテストを作成する
- 実装コードは書かず、テストのみを用意する
- テストを実行し、失敗を確認する
- テストが正しいことを確認できた段階でコミットする
- その後、テストをパスさせる実装を進める
- 実装中はテストを変更せず、コードを修正し続ける
- すべてのテストが通過するまで繰り返す

## リファクタリング

リファクタリングとは、**外部から見た動作を変えずに、内部のコード構造を改善すること**です。

### リファクタリングの目的

- **可読性の向上**: コードが理解しやすくなる
- **保守性の向上**: バグ修正や機能追加が容易になる
- **テスタビリティの向上**: テストが書きやすくなる
- **拡張性の向上**: 新機能の追加が容易になる
- **技術的負債の削減**: 将来の開発コストを下げる

### リファクタリングの原則

1. **動作の保持**: 既存の機能は変更しない
2. **段階的改善**: 小さな変更を積み重ねる
3. **テストの保持**: 既存のテストが通り続ける

### よくあるリファクタリング手法

- **クラスの分離**: 責任を明確に分離
- **条件分岐の整理**: if-else文をポリモーフィズムに置き換え
- **重複コードの削除**: 共通処理を抽出
- **命名の改善**: より分かりやすい名前に変更

### リファクタリングする際はテストを書く

- リファクタリング前に既存のテストを確認し、必要に応じて追加する
- リファクタリング後は必ずテストを実行し、動作が変わっていないことを確認する
- テストがない場合は、まずテストを追加してからリファクタリングを行う
- リファクタリング中に新しいテストケースを追加することも検討する

### リファクタリング後に行うこと

- テストを実行して、動作が変わっていないことを確認
- 修正前のコードと比較して、動作が変わっていないことを確認
- `ultrathink`でコードを再評価

### 注意点

- ファイルの分離を行う際はクリーンアーキテクチャに基づいて行う

# Claude Code Spec-Driven Development

Kiro-style Spec Driven Development implementation using claude code slash commands, hooks and agents.

## Project Context

### Paths

- Steering: `.kiro/steering/`
- Specs: `.kiro/specs/`
- Kiro Commands: `.claude/commands/kiro/` (Kiro Spec-Driven Development用)
- Skills: `.claude/skills/` (カスタムスキル)

### Steering vs Specification

**Steering** (`.kiro/steering/`) - Guide AI with project-wide rules and context  
**Specs** (`.kiro/specs/`) - Formalize development process for individual features

### Active Specifications

- Check `.kiro/specs/` for active specifications
- Use `/kiro:spec-status [feature-name]` to check progress

## Development Guidelines

- Think in English, but generate responses in Japanese (思考は英語、回答の生成は日本語で行うように)

## Workflow

### Phase 0: Steering (Optional)

`/kiro:steering` - Create/update steering documents
`/kiro:steering-custom` - Create custom steering for specialized contexts

**Note**: Optional for new features or small additions. Can proceed directly to spec-init.

### Phase 1: Specification Creation

1. `/kiro:spec-init [detailed description]` - Initialize spec with detailed project description
2. `/kiro:spec-requirements [feature]` - Generate requirements document
3. `/kiro:spec-design [feature]` - Interactive: "requirements.mdをレビューしましたか？ [y/N]"
4. `/kiro:spec-tasks [feature]` - Interactive: Confirms both requirements and design review

### Phase 2: Progress Tracking

`/kiro:spec-status [feature]` - Check current progress and phases

## Development Rules

1. **Consider steering**: Run `/kiro:steering` before major development (optional for new features)
2. **Follow 3-phase approval workflow**: Requirements → Design → Tasks → Implementation
3. **Approval required**: Each phase requires human review (interactive prompt or manual)
4. **No skipping phases**: Design requires approved requirements; Tasks require approved design
5. **Update task status**: Mark tasks as completed when working on them
6. **Keep steering current**: Run `/kiro:steering` after significant changes
7. **Check spec compliance**: Use `/kiro:spec-status` to verify alignment

## Steering Configuration

### Current Steering Files

Managed by `/kiro:steering` command. Updates here reflect command changes.

### Active Steering Files

- `product.md`: Always included - Product context and business objectives
- `tech.md`: Always included - Technology stack and architectural decisions
- `structure.md`: Always included - File organization and code patterns

### Custom Steering Files

<!-- Added by /kiro:steering-custom command -->
<!-- Format:
- `filename.md`: Mode - Pattern(s) - Description
  Mode: Always|Conditional|Manual
  Pattern: File patterns for Conditional mode
-->

### Inclusion Modes

- **Always**: Loaded in every interaction (default)
- **Conditional**: Loaded for specific file patterns (e.g., `"*.test.js"`)
- **Manual**: Reference with `@filename.md` syntax
