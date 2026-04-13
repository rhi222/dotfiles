# Prompt settings (tide)
# now use tide. install via fisher
# https://github.com/IlanCosman/tide
# shorten current directory length
# https://github.com/IlanCosman/tide/issues/227
# NOTE: set -U は永続化されるため、初回セットアップ時に手動実行すること
# set -U tide_prompt_min_cols 10000
set -g tide_prompt_min_cols 10000
# right promptは非表示
# ターミナルコピペ時に不便なため
# items(list)は空で設定
# https://github.com/IlanCosman/tide/wiki/Configuration#right_prompt
# set -U tide_right_prompt_items
set -g tide_right_prompt_items