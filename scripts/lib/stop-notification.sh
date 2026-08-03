#!/bin/bash
# Claude Code の Stop フック通知の、タイトルと本文を組み立てる共通関数。
#
# 使い方:
#   source "$HOME/scripts/lib/stop-notification.sh"
#   title=$(stop_notification_title "$cwd")
#   body=$(stop_notification_summary "$transcript_path")
#
# 依存: jq / git
#
# 環境変数:
#   STOP_NOTIFICATION_SUMMARY_MAX - 本文の最大文字数（デフォルト 120）

STOP_NOTIFICATION_FALLBACK="タスクが完了しました"

# セッションの作業対象を示すタイトルを返す。例: "✅ dotfiles (main)"
stop_notification_title() {
  local cwd="${1:-}"
  local default_title="Claude Code 完了"

  if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    printf '%s' "$default_title"
    return 0
  fi

  local name branch
  name=$(basename "$cwd")
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""

  # detached HEAD ではブランチ名として意味をなさないので出さない
  if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
    printf '✅ %s (%s)' "$name" "$branch"
  else
    printf '✅ %s' "$name"
  fi
}

# トランスクリプトから最後のアシスタント発言を1行に整形して返す。
# 取れない場合は固定文言にフォールバックする。
stop_notification_summary() {
  local transcript="${1:-}"
  local max="${STOP_NOTIFICATION_SUMMARY_MAX:-120}"
  # ${#text} と ${text:0:max} をバイト数でなく文字数で扱わせる。
  # local なので呼び出し元のロケールは汚さない
  local LC_ALL=C.UTF-8

  if [[ -z "$transcript" || ! -r "$transcript" ]]; then
    printf '%s' "$STOP_NOTIFICATION_FALLBACK"
    return 0
  fi

  local text
  # サブエージェント(isSidechain)の発言はメインの結論ではないので除く。
  # gsub で textブロック内の改行を潰し、1ブロック=1行にしてから末尾を採る
  text=$(
    jq -r 'select(.type == "assistant" and (.isSidechain != true))
           | .message.content[]?
           | select(.type == "text")
           | .text
           | gsub("\\s+"; " ")' "$transcript" 2>/dev/null |
      sed -e 's/`//g' -e 's/\*//g' -e 's/^ *#\+ *//' -e 's/^ *//' -e 's/ *$//' |
      grep -v '^$' |
      tail -n 1
  )

  if [[ -z "$text" ]]; then
    printf '%s' "$STOP_NOTIFICATION_FALLBACK"
    return 0
  fi

  if ((${#text} > max)); then
    text="${text:0:max}…"
  fi

  printf '%s' "$text"
}
