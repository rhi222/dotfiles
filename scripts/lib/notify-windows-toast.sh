#!/bin/bash
# Windows BurntToast 通知を送るための共通関数。
# WSL2 + Windows PowerShell + BurntToast モジュールが前提。
#
# 使い方:
#   source "$HOME/scripts/lib/notify-windows-toast.sh"
#   send_windows_toast "タイトル" "メッセージ"                       # icon なし
#   send_windows_toast "タイトル" "メッセージ" "/path/to/icon.png"  # icon あり

send_windows_toast() {
  local title="$1"
  local message="$2"
  local icon_path="${3:-}"

  # シングルクォートを PowerShell の literal '...' 用に '' へエスケープ
  title="${title//\'/\'\'}"
  message="${message//\'/\'\'}"

  if [[ -n "$icon_path" && -f "$icon_path" ]]; then
    local win_icon_path
    win_icon_path=$(wslpath -w "$icon_path")
    powershell.exe -NoProfile -Command "
      Import-Module BurntToast -ErrorAction SilentlyContinue
      New-BurntToastNotification -Text '$title', '$message' -AppLogo '$win_icon_path'
    "
  else
    powershell.exe -NoProfile -Command "
      Import-Module BurntToast -ErrorAction SilentlyContinue
      New-BurntToastNotification -Text '$title', '$message'
    "
  fi
}
