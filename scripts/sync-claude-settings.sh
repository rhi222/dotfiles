#!/bin/bash
# ~/.claude/settings.json とリポジトリ版を同期する。
#
#   bash scripts/sync-claude-settings.sh pull [--dry-run]  # 実ファイル -> リポジトリ
#   bash scripts/sync-claude-settings.sh push [--force]    # リポジトリ -> 実ファイル
#   bash scripts/sync-claude-settings.sh status            # 差分の確認だけ
#
# なぜシンボリックリンクではないのか:
#   Claude Code は /config でのテーマ変更・プラグインの有効無効・skillOverrides
#   などを実行時に settings.json へ書き戻す。この書き込みは一時ファイル + rename
#   で行われるため、~/.claude/settings.json をリポジトリへの symlink にしていても
#   実ファイルに置き換えられてしまう（CLAUDE.md や commands/ は書き込まれないので
#   symlink のまま残る）。リンクで戦っても必ず外れるので、コピー同期にしている。
#
# 通常運用は pull。実ファイルを正とし、リポジトリがそれを追いかける。
# push は新環境の bootstrap 用（dotfilesLink.sh から呼ばれる）。
#
# 環境変数（テスト用オーバーライド）:
#   CLAUDE_SETTINGS_LIVE - 実ファイルのパス
#   CLAUDE_SETTINGS_REPO - リポジトリ側のパス
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/settings-sync.sh
source "$SCRIPT_DIR/lib/settings-sync.sh"

LIVE="${CLAUDE_SETTINGS_LIVE:-$HOME/.claude/settings.json}"
REPO="${CLAUDE_SETTINGS_REPO:-$REPO_ROOT/.config/claude/settings.json}"

usage() {
  cat >&2 <<'USAGE'
使い方: sync-claude-settings.sh <pull|push|status> [オプション]

  pull [--dry-run]  ~/.claude/settings.json をリポジトリに取り込む（通常はこちら）
  push [--force]    リポジトリの内容を ~/.claude/settings.json に書き出す
  status            差分の有無を表示するだけ
USAGE
}

# JSONとして読めなければ非ゼロ。壊れた設定を相手側へ伝播させないための門番
read_normalized() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: $label が見つかりません: $path" >&2
    return 1
  fi
  if ! jq -S . "$path" 2>/dev/null; then
    echo "ERROR: $label が正しいJSONではありません: $path" >&2
    return 1
  fi
}

# マスク対象キーの判定に使う ERE。辞書が無ければ空（＝マスクしない）。
# 新環境で bootstrap 前に同期が壊れるのを避けるため、辞書不在は許容する。
secret_regex() {
  local patterns="${SECRET_PATTERNS:-$HOME/.config/dotfiles/secret-patterns.txt}"
  [[ -f "$patterns" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$patterns" | paste -sd'|'
}

# stdin の JSON から機密エントリを落として stdout に出す。
#
# 対象は enabledPlugins と extraKnownMarketplaces のキー。このリポジトリは public なので、
# 社内プラグイン名とその git URL を入れない。値は見ずキー名だけで判定する
# （キーが "<plugin>@<marketplace>" 形式で、marketplace 名に社名が入るため）。
mask_secrets() {
  local re
  re=$(secret_regex)
  if [[ -z "$re" ]]; then
    jq -S .
    return
  fi
  jq -S --arg re "$re" '
    def strip(k):
      if has(k) then .[k] |= with_entries(select(.key | test($re) | not)) else . end;
    strip("enabledPlugins") | strip("extraKnownMarketplaces")
  '
}

# リポジトリ版($1) に実ファイル($2) の機密エントリを戻して stdout に出す。
# push でリポジトリ版を書き出すとき、実ファイル側にしかない社内設定を消さないために使う。
merge_secrets() {
  local repo_json="$1" live_json="$2" re
  re=$(secret_regex)
  if [[ -z "$re" ]]; then
    printf '%s\n' "$repo_json" | jq -S .
    return
  fi
  jq -S -n --argjson repo "$repo_json" --argjson live "$live_json" --arg re "$re" '
    def secrets(src; k):
      if (src | has(k)) then (src[k] | with_entries(select(.key | test($re)))) else {} end;
    def restore(k):
      (secrets($live; k)) as $s
      | if ($s | length) == 0 then . else .[k] = ((.[k] // {}) + $s) end;
    $repo | restore("enabledPlugins") | restore("extraKnownMarketplaces")
  '
}

cmd_pull() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=1

  local content
  content=$(read_normalized "$LIVE" "実ファイル") || return 1
  # 社内固有のプラグイン設定はリポジトリに入れない（public のため）
  content=$(printf '%s\n' "$content" | mask_secrets)

  settings_sync_reconcile_pull "$content" "$REPO" "$dry_run" \
    "変更なし: リポジトリは実ファイルと一致しています" \
    "更新あり（--dry-run のため書き込みません）: $REPO" \
    "更新: $REPO に実ファイルの内容を取り込みました"
}

cmd_push() {
  local force=0
  [[ "${1:-}" == "--force" ]] && force=1

  local content
  content=$(read_normalized "$REPO" "リポジトリ版") || return 1

  if [[ ! -f "$LIVE" ]]; then
    settings_sync_write_if_changed "$content" "$LIVE"
    echo "作成: $LIVE をリポジトリ版から作成しました"
    return 0
  fi

  local live_content
  live_content=$(read_normalized "$LIVE" "実ファイル") || {
    # 実ファイルが壊れている場合は --force でのみ復旧させる
    if [[ "$force" -eq 1 ]]; then
      settings_sync_write_if_changed "$content" "$LIVE"
      echo "上書き: 壊れた $LIVE をリポジトリ版で復旧しました"
      return 0
    fi
    return 1
  }

  # 実ファイル側の機密エントリはリポジトリに存在しないので、比較はマスク後どうしで行う。
  # そうしないと機密の有無だけで常に「差分あり」になり、push が拒否され続ける。
  local live_masked
  live_masked=$(printf '%s\n' "$live_content" | mask_secrets)

  # 実ファイル側にしかない社内設定を消さないよう、書き戻す前にマージする
  local merged
  merged=$(merge_secrets "$content" "$live_content")

  local reject_header
  reject_header=$(
    cat <<EOF
ERROR: 実ファイルとリポジトリに差分があるため push しません。
  実ファイル: $LIVE
  リポジトリ: $REPO

実ファイル側の変更（/config での操作など）を残すなら pull を、
リポジトリ側で上書きしてよいなら push --force を実行してください。
差分:
EOF
  )

  settings_sync_reconcile_push "$content" "$live_masked" "$force" "$merged" "$LIVE" \
    "$reject_header" \
    "変更なし: 実ファイルはリポジトリと一致しています" \
    "上書き: $LIVE をリポジトリ版で上書きしました（社内設定は保持）"
}

cmd_status() {
  local live_content repo_content
  live_content=$(read_normalized "$LIVE" "実ファイル") || return 1
  repo_content=$(read_normalized "$REPO" "リポジトリ版") || return 1

  # push と同じく、機密エントリの有無は差分として扱わない
  live_content=$(printf '%s\n' "$live_content" | mask_secrets)

  settings_sync_reconcile_status "$repo_content" "$live_content" \
    "一致: 実ファイルとリポジトリは同じ内容です" \
    "差分あり（左: リポジトリ / 右: 実ファイル）"
}

case "${1:-}" in
  pull) shift && cmd_pull "$@" ;;
  push) shift && cmd_push "$@" ;;
  status) shift && cmd_status "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
