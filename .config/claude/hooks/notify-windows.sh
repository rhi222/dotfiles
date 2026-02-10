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

# アイコンパスを取得（スクリプトと同じディレクトリ）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_PATH="$SCRIPT_DIR/claude-icon.png"

# BurntToastでWindows通知を送信
if [[ -f "$ICON_PATH" ]]; then
  WIN_ICON_PATH=$(wslpath -w "$ICON_PATH")
  powershell.exe -NoProfile -Command "
    Import-Module BurntToast -ErrorAction SilentlyContinue
    New-BurntToastNotification -Text '$TITLE', '$MESSAGE' -AppLogo '$WIN_ICON_PATH'
  "
else
  powershell.exe -NoProfile -Command "
    Import-Module BurntToast -ErrorAction SilentlyContinue
    New-BurntToastNotification -Text '$TITLE', '$MESSAGE'
  "
fi

exit 0
