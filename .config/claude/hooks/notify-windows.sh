#!/bin/bash
# Claude Code完了時にWindows通知を送信するhook
#
# =============================================================================
# 環境構築
# =============================================================================
#
# 依存関係:
#   - jq: JSONパース用（WSL側）
#   - BurntToast: Windows通知用PowerShellモジュール
#
# BurntToast:
#   GitHub: https://github.com/Windos/BurntToast
#
#   インストール（PowerShell管理者権限で実行）:
#     Install-Module -Name BurntToast -Scope CurrentUser
#
#   確認コマンド:
#     Get-Module -ListAvailable BurntToast
#
#   テスト通知:
#     New-BurntToastNotification -Text "Test", "Hello"
#
# 動作確認（WSL側）:
#   echo '{"hook_event_name":"Stop"}' | ~/.config/claude/hooks/notify-windows.sh
#
# 注意:
#   Windowsの「応答不可」（集中モード）がオンだと通知がブロックされます
#   設定 → システム → 通知 で確認してください
#
# =============================================================================

# アイコンパスを取得（スクリプトと同じディレクトリ）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_PATH="$SCRIPT_DIR/claude-icon.png"

# Windows BurntToast 通知の共通関数 (send_windows_toast)
# shellcheck source=../../../scripts/lib/notify-windows-toast.sh
source "$HOME/scripts/lib/notify-windows-toast.sh"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

case "$EVENT" in
  "Stop")
    TITLE="Claude Code 完了"
    MESSAGE="タスクが完了しました"
    ;;
  "Notification")
    TITLE="Claude Code"
    MESSAGE=$(echo "$INPUT" | jq -r '.message // "入力を待っています"')
    ;;
  *)
    TITLE="Claude Code"
    MESSAGE="イベント: $EVENT"
    ;;
esac

send_windows_toast "$TITLE" "$MESSAGE" "$ICON_PATH"

# Stop時に日報チェックをバックグラウンド実行（フラグファイルで有効化）
NIPPO_NOTIFY_FLAG="$HOME/.config/nippo-notify-enabled"
if [[ "$EVENT" == "Stop" && -f "$NIPPO_NOTIFY_FLAG" ]]; then
  NIPPO_CHECK="$HOME/scripts/nippo-check.sh"
  if [[ -x "$NIPPO_CHECK" ]]; then
    (
      nippo_msg=$(timeout 5 "$NIPPO_CHECK" stop 2>/dev/null)
      status=$?
      if [[ $status -ne 0 && -n "$nippo_msg" ]]; then
        send_windows_toast "日報チェック" "$nippo_msg" "$ICON_PATH"
      fi
    ) & disown
  fi
fi

exit 0
