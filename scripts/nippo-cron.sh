#!/bin/bash
# 日報リマインド（cron用ラッパー）
# crontab設定例:
#   0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh >> $HOME/.nippo-cron.log 2>&1

set -uo pipefail

# cron環境用PATH設定（PowerShell実行に必要）
export PATH="$PATH:/mnt/c/Windows/System32/WindowsPowerShell/v1.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIPPO_CHECK="$SCRIPT_DIR/nippo-check.sh"

# フラグファイルで有効化チェック
NIPPO_NOTIFY_FLAG="$HOME/.config/nippo-notify-enabled"
if [[ ! -f "$NIPPO_NOTIFY_FLAG" ]]; then
  exit 0
fi

# nippo-check.shの存在確認
if [[ ! -x "$NIPPO_CHECK" ]]; then
  echo "$(date): nippo-check.sh not found" >&2
  exit 1
fi

# 作業時間フィルタ（平日9:00-19:00のみ）
DOW=$(date +%u)
HOUR=$(date +%H | sed 's/^0//')

if [[ "$DOW" -ge 6 ]]; then
  exit 0
fi

if [[ "$HOUR" -lt 9 || "$HOUR" -ge 20 ]]; then
  exit 0
fi

# 日報チェック実行
nippo_msg=$(timeout 5 "$NIPPO_CHECK" cron 2>/dev/null)
check_exit=$?

if [[ "$check_exit" -ne 0 && -n "$nippo_msg" ]]; then
  # アイコンパスを取得
  HOOK_DIR="$HOME/.config/claude/hooks"
  ICON_PATH="$HOOK_DIR/claude-icon.png"

  TITLE="日報リマインド（定期）"
  # シングルクォートをエスケープ（PowerShell用）
  TITLE="${TITLE//\'/\'\'}"
  nippo_msg="${nippo_msg//\'/\'\'}"

  if [[ -f "$ICON_PATH" ]]; then
    WIN_ICON_PATH=$(wslpath -w "$ICON_PATH")
    powershell.exe -NoProfile -Command "
      Import-Module BurntToast -ErrorAction SilentlyContinue
      New-BurntToastNotification -Text '$TITLE', '$nippo_msg' -AppLogo '$WIN_ICON_PATH'
    "
  else
    powershell.exe -NoProfile -Command "
      Import-Module BurntToast -ErrorAction SilentlyContinue
      New-BurntToastNotification -Text '$TITLE', '$nippo_msg'
    "
  fi

  echo "$(date): 通知送信: $nippo_msg"
else
  echo "$(date): 問題なし"
fi

exit 0
