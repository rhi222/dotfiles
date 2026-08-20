# Prompt settings (tide)
# now use tide. install via fisher
# https://github.com/IlanCosman/tide
#
# ここにあるのは2つだけ。tide の見た目を決める残り154個の変数は universal 変数で、
# ~/.config/fish/fish_variables は追跡していない。そちらは新環境で
# `tide configure --auto` を1回流して確定させる（docs/bootstrap.md を見ること）。
# 対話の `tide configure` で答えを間違えるとプロンプトが3行になるのはこのため。

# universal変数が残っていると set -g で上書きできないため、まず削除してから設定する。
# これにより新環境/既存環境のどちらでも確実に効く。
set -e -U tide_prompt_min_cols 2>/dev/null
set -e -U tide_right_prompt_items 2>/dev/null

# shorten current directory length
# https://github.com/IlanCosman/tide/issues/227
set -g tide_prompt_min_cols 10000

# right promptは非表示（ターミナルコピペ時に不便なため）
# https://github.com/IlanCosman/tide/wiki/Configuration#right_prompt
set -g tide_right_prompt_items
