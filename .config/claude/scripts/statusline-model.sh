#!/bin/bash
# ccstatusline の custom-command ウィジェット用。モデル名を描画する。
#
# ccstatusline 標準の model ウィジェットは色が固定値のため「Fable のときだけ目立たせる」が
# できない。custom-command は stdin に Claude Code の statusline JSON を受け取り、
# preserveColors: true なら stdout の ANSI をそのまま通すので、ここで色を出し分ける。
#
#   Fable    → ⚡FABLE 5⚡（オリーブ背景・カーキ文字・太字の反転バッジ）
#   それ以外 → Model: <名前>（cyan。標準ウィジェットと同じ見た目）
#
# Fable の判定は model.id の前方一致と display_name の部分一致の両方で行う。
# display_name の実際の表記を実機で確認できていないため、どちらか一方でも拾えるようにする。
#
# 動作確認: bash tests/settings/test-statusline-model.sh
set -uo pipefail

CYAN=$'\033[36m'
# 淡いカーキ文字(38;5;186) + くすんだオリーブ背景(48;5;58) + 太字。
# 純色の黄背景(226)は目に痛いので、他ウィジェット（96/59/178）と同じ低彩度の系統に合わせる
BADGE=$'\033[1;38;5;186;48;5;58m'
RESET=$'\033[0m'

# jq が無い環境で statusline 全体を壊さないためのフォールバック。
# 外部コマンドを一切使わずに返す（PATH が壊れている場合も想定する）
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "${CYAN}Model: ?${RESET}"
  exit 0
fi

input=$(cat)

# display_name が無ければ id を使う（標準の model ウィジェットと同じフォールバック）
# 末尾の "(1M context)" のような括弧書きは落とす（同上）
# 空行を保つため mapfile で受ける（id が空でも name の位置がずれないようにする）
mapfile -t fields < <(printf '%s' "$input" | jq -r '
  (.model // {}) as $m
  | ($m.id // "")
  , (($m.display_name // $m.id // "") | sub("\\s*\\(.*\\)$"; ""))
' 2>/dev/null)

id=${fields[0]:-}
name=${fields[1]:-}

if [[ -z "$name" ]]; then
  exit 0
fi

id_lower=${id,,}
name_lower=${name,,}

if [[ "$id_lower" == claude-fable* || "$name_lower" == *fable* ]]; then
  printf '%s' "${BADGE}⚡${name^^}⚡${RESET}"
else
  printf '%s' "${CYAN}Model: ${name}${RESET}"
fi
