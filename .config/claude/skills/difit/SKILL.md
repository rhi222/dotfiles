---
name: difit
description: difitでステージされた変更をブラウザでレビューする。「差分を見せて」「diffを確認」「変更をレビュー」「ブラウザで見たい」「difit」などで使用。
allowed-tools: Bash(difit:*), Bash(npx difit:*), Bash(git status:*), Bash(git diff:*)
argument-hint: "[引数] (例: staged, ., path/to/file)"
---

## 概要

difit（GitHub-likeなdiffビューア）を使って、変更内容をブラウザで視覚的にレビューするスキルです。

## 手順

1. **ステージ状況を確認する**

   ```bash
   git status
   ```

2. **difitを起動する**

   - `$ARGUMENTS` が指定されている場合: `difit $ARGUMENTS` を実行
   - ステージされた変更がある場合: `difit staged` を実行
   - ステージされた変更がない場合: `difit .` を実行（全未コミット変更を表示）

3. **ユーザーに案内する**

   ブラウザでdiffビューが開きます。レビューが完了したら `/git-commit` でコミットしてください。
