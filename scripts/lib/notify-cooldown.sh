#!/bin/bash
# 同じ通知が短時間に何度も飛ぶのを抑止する共通関数。
#
# 使い方:
#   source "$HOME/scripts/lib/notify-cooldown.sh"
#   if notify_cooldown_should_send "$HOME/.cache/foo-state" "$msg"; then
#     send_windows_toast "タイトル" "$msg"
#   fi
#
# 環境変数:
#   NOTIFY_COOLDOWN_SEC - 同一メッセージを再通知しない秒数（デフォルト 3600）
#   NOTIFY_COOLDOWN_NOW - 現在時刻(epoch)の上書き。テスト用
#
# stateファイル形式:
#   1行目       最終送信時刻(epoch)
#   2行目以降   そのとき送ったメッセージ（改行やタブを含んでもよい）
#
# 内容が前回と変わっていれば、クールダウン中でも送る。
# 「未完了タスク3件 → 5件」のように状況が動いたことは知らせたいため。

# 送信すべきなら 0、抑止するなら 1 を返す。
# 送信すると判断したときだけ state を更新するので、抑止のたびに
# クールダウン窓が延びていくことはない。
notify_cooldown_should_send() {
  local state_file="$1"
  local message="$2"
  local cooldown="${NOTIFY_COOLDOWN_SEC:-3600}"
  local now="${NOTIFY_COOLDOWN_NOW:-$(date +%s)}"

  local last_ts="" last_msg=""
  if [[ -r "$state_file" ]]; then
    last_ts=$(head -n 1 "$state_file")
    last_msg=$(tail -n +2 "$state_file")
  fi

  # タイムスタンプが数値でない（state破損・初回）ときは送信側に倒す
  if [[ "$last_ts" =~ ^[0-9]+$ && "$last_msg" == "$message" ]]; then
    if ((now - last_ts < cooldown)); then
      return 1
    fi
  fi

  mkdir -p "$(dirname "$state_file")" 2>/dev/null
  printf '%s\n%s' "$now" "$message" >"$state_file"
  return 0
}
