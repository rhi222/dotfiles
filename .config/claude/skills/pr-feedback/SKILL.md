---
name: pr-feedback
description: Pull Requestのレビューコメントに対応する。「レビュー対応」「指摘対応」「コメント対応」「フィードバック対応」などで使用。コメントを優先度分類し、エラー分析3段階アプローチで根本解決を図る。
allowed-tools: Bash(gh:*)
disable-model-invocation: true
argument-hint: "<PR番号>"
---

Pull Request のレビューコメントを効率的に対応し、エラー分析 3 段階アプローチで根本解決を図ります。

## 使い方

`$ARGUMENTS` でPR番号を指定します。

```bash
# レビューコメントの取得と分析
gh pr view $ARGUMENTS --comments

# コメントを must/imo/nits/q に分類
gh pr view $ARGUMENTS --comments | head -20
```

## コメント分類

レビューコメントを must/imo/nits/q に分類して対応順序を決定する。詳細は `references/comment-classification.md` を参照。

## エラー分析

CIエラーやバグ報告には3段階アプローチ（情報収集 → 根本原因分析 → 解決策実装）で対応する。詳細は `references/error-analysis.md` を参照。

## 対応フロー

1. **コメント分析**: 優先度別の分類
2. **修正計画**: 対応順序の決定
3. **段階的修正**: Critical → High → Medium → Low
4. **品質確認**: テスト・リント・ビルド
5. **進捗報告**: 具体的な修正内容の説明

## 修正後の確認

プロジェクトのテストスイート・リンター・ビルドコマンドを実行する。
プロジェクトタイプ（package.json, Cargo.toml, go.mod 等）から適切なコマンドを判別すること。

## 返信テンプレート

返信の書き方は `references/reply-templates.md` を参照。

## 注意事項

- **優先度遵守**: Critical → High → Medium → Low の順で対応する。重大な問題を先に解決することで、後続の修正が無駄になるリスクを避ける。
- **テストファースト**: 修正前に回帰テストを確認する。既存のテストが通ることを先に確認しておくことで、修正による意図しない影響を検出できる。
- **明確な報告**: 修正内容と確認方法を具体的に記述
- **建設的対話**: 技術的根拠に基づく丁寧なコミュニケーション
