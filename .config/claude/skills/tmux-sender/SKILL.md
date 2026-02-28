---
name: tmux-sender
description: tmux の別ペインにコマンドを送信する。「ペインで実行して」「tmuxで送信」などのリクエストで使用。
allowed-tools: Bash(tmux:*)
argument-hint: "<送信するコマンド>"
---

# tmux コマンド送信スキル

## 手順

1. `tmux list-panes` でペイン一覧を確認（active のペインが自分自身）
2. 送信先のペイン番号を特定する
3. `tmux send-keys -t <ペイン番号> '<コマンド>' Enter` で送信・実行

## ペイン指定方法

- 番号指定: `-t 0`, `-t 1`
- 相対指定: `-t :.+`（次のペイン）, `-t :.-`（前のペイン）
- セッション指定: `-t session:window.pane`

## 注意事項

- コマンドにシングルクォートが含まれる場合は、ダブルクォートで囲むか適切にエスケープする
  - 例: `tmux send-keys -t 1 "echo 'hello'" Enter`
- 送信先ペインの状態を確認したい場合: `tmux capture-pane -t <ペイン番号> -p`
