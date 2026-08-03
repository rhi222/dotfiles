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
# Stop通知の文面組み立て (stop_notification_title / stop_notification_summary)
# shellcheck source=../../../scripts/lib/stop-notification.sh
source "$HOME/scripts/lib/stop-notification.sh"
# 重複通知の抑止 (notify_cooldown_should_send)
# shellcheck source=../../../scripts/lib/notify-cooldown.sh
source "$HOME/scripts/lib/notify-cooldown.sh"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

case "$EVENT" in
  "Stop")
    # どのリポジトリで何を終えたのかが通知だけで分かるようにする
    TITLE=$(stop_notification_title "$(echo "$INPUT" | jq -r '.cwd // empty')")
    MESSAGE=$(stop_notification_summary "$(echo "$INPUT" | jq -r '.transcript_path // empty')")
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
#
# Stopは応答が終わるたびに発火するので、素通しにすると完了通知とセットで
# 日報通知も毎回鳴る。二段で絞る:
#   1. 実行ゲート  … チェック自体を10分に1回に制限する。日報は /mnt/c (9p)
#                    上にあり1ファイル操作あたり数秒かかるため、毎回走らせない
#   2. 通知クールダウン … 同じ内容の通知は60分に1回まで
NIPPO_NOTIFY_FLAG="$HOME/.config/nippo-notify-enabled"
NIPPO_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-nippo-notify"
if [[ "$EVENT" == "Stop" && -f "$NIPPO_NOTIFY_FLAG" ]]; then
  NIPPO_CHECK="$HOME/scripts/nippo-check.sh"
  if [[ -x "$NIPPO_CHECK" ]]; then
    (
      if ! NOTIFY_COOLDOWN_SEC=600 \
        notify_cooldown_should_send "$NIPPO_CACHE_DIR/last-run" "nippo-check"; then
        exit 0
      fi
      nippo_msg=$(timeout 30 "$NIPPO_CHECK" stop 2>/dev/null)
      status=$?
      if [[ $status -ne 0 && -n "$nippo_msg" ]] &&
        notify_cooldown_should_send "$NIPPO_CACHE_DIR/last-notify" "$nippo_msg"; then
        send_windows_toast "日報チェック" "$nippo_msg" "$ICON_PATH"
      fi
    ) &
    disown
  fi
fi

exit 0
