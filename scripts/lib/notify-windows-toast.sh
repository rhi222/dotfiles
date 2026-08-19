#!/bin/bash
# Windows BurntToast 通知を送るための共通関数。
# WSL2 + Windows PowerShell + BurntToast モジュールが前提。
#
# 使い方:
#   source "$HOME/scripts/lib/notify-windows-toast.sh"
#   send_windows_toast "タイトル" "メッセージ"                       # icon なし
#   send_windows_toast "タイトル" "メッセージ" "/path/to/icon.png"  # icon あり
#
# BurntToast が入っていない端末では、通知を出さずに黙って成功する。
# 以前は `Import-Module BurntToast -ErrorAction SilentlyContinue` だけを付けていたが、
# これは import の失敗しか黙らせない。モジュールが無いと次行の
# New-BurntToastNotification が CommandNotFoundException を吐き、PowerShell の
# スタックトレースが呼び出し元の出力に混ざっていた（daily-update・nippo-cron・
# Claude Code の Stop フックの3経路）。ガードは cmdlet 側に置く。
#
# 判定は PowerShell 側の1プロセス内で行う。Import-Module に実測10秒かかるため、
# bash から別プロセスで discovery すると通知1回のコストが倍になる。
#
# 不在の通知に Write-Error は使わない。エラーレコードとして整形され、
# CategoryInfo / FullyQualifiedErrorId 付きの複数行ブロックになるので、
# 消したいノイズを別のノイズに置き換えるだけになる。stderr へ素の1行を書く。

# 通知本体を組み立てて実行する。BurntToast が無ければ理由を1行出して何もしない。
# 呼び出し元は powershell.exe が無い場合（WSL2 以外）と同じ扱いにできる。
__burnt_toast_invoke() {
  local cmdlet_args="$1"
  powershell.exe -NoProfile -Command "
      if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        [Console]::Error.WriteLine('BurntToast module not installed; skipping toast')
        exit 0
      }
      Import-Module BurntToast
      New-BurntToastNotification $cmdlet_args
    "
}

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
    __burnt_toast_invoke "-Text '$title', '$message' -AppLogo '$win_icon_path'"
  else
    __burnt_toast_invoke "-Text '$title', '$message'"
  fi
}
