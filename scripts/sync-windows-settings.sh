#!/bin/bash
# Windows 側にあって symlink できない設定ファイルをリポジトリと同期する。
#
#   bash scripts/sync-windows-settings.sh status [target]
#   bash scripts/sync-windows-settings.sh pull   [target] [--dry-run]  # 実ファイル -> リポジトリ
#   bash scripts/sync-windows-settings.sh push   [target] [--force]    # リポジトリ -> 実ファイル
#
# target を省略すると全部が対象。
#
#   wslconfig  %USERPROFILE%\.wslconfig
#   terminal   Windows Terminal の settings.json
#
# なぜシンボリックリンクではないのか（理由が2つある）:
#   1. 実体が /mnt/c（NTFS）にある。WSL から張った symlink を Windows 側は解釈しない。
#   2. Windows Terminal は distro を検出するとプロファイルを settings.json へ自動追記する。
#      ~/.claude/settings.json と同じ書き戻し問題で、リンクにしても外れる。
#
# 通常運用は pull。実ファイルを正とし、リポジトリがそれを追いかける
# （sync-claude-settings.sh と同じ思想）。
#
# push は新環境の bootstrap 用だが、dotfilesLink.sh からは呼ばない。
# .wslconfig の memory 値は「そのマシンの物理RAMと Windows 側の使用量」から出した実測値で、
# 別スペックの端末へ自動で配ると不適切になるため、人間が判断して手で叩く。
#
# 環境変数（テスト用オーバーライド）:
#   WSLCONFIG_LIVE / WSLCONFIG_REPO
#   WT_SETTINGS_LIVE / WT_SETTINGS_REPO
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/settings-sync.sh
source "$SCRIPT_DIR/lib/settings-sync.sh"

usage() {
  cat >&2 <<'USAGE'
使い方: sync-windows-settings.sh <pull|push|status> [target] [オプション]

  target: wslconfig | terminal（省略時は全部）

  pull [--dry-run]  実ファイルをリポジトリに取り込む（通常はこちら）
  push [--force]    リポジトリの内容を実ファイルに書き出す
  status            差分の有無を表示するだけ
USAGE
}

# Windows のユーザー名。deploy-ahk-script.sh と同じ解決方法に揃えている
win_user() {
  cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r\n'
}

# Store 版 Windows Terminal の LocalState。パッケージ名は固定だがハッシュ部が
# 変わりうるので glob で拾う。Preview 版は別パッケージ名なので巻き込まない
find_wt_settings() {
  local user="$1" d
  for d in "/mnt/c/Users/$user/AppData/Local/Packages/Microsoft.WindowsTerminal_"*/LocalState; do
    [[ -d "$d" ]] && {
      printf '%s/settings.json' "$d"
      return 0
    }
  done
  return 1
}

TARGETS=(wslconfig terminal)

# target ごとの (実ファイル, リポジトリ, 正規化の種類) を返す。
# 実ファイルのパス解決は環境変数が最優先。テストが /mnt/c を触らずに済むようにするため
target_live() {
  case "$1" in
    wslconfig)
      if [[ -n "${WSLCONFIG_LIVE:-}" ]]; then
        printf '%s' "$WSLCONFIG_LIVE"
      else
        printf '/mnt/c/Users/%s/.wslconfig' "$(win_user)"
      fi
      ;;
    terminal)
      if [[ -n "${WT_SETTINGS_LIVE:-}" ]]; then
        printf '%s' "$WT_SETTINGS_LIVE"
      else
        find_wt_settings "$(win_user)"
      fi
      ;;
  esac
}

target_repo() {
  case "$1" in
    wslconfig) printf '%s' "${WSLCONFIG_REPO:-$REPO_ROOT/.config/wsl/.wslconfig}" ;;
    terminal) printf '%s' "${WT_SETTINGS_REPO:-$REPO_ROOT/.config/windows-terminal/settings.json}" ;;
  esac
}

# json は jq -S で正規化して差分を意味のある変更だけにする。
# .wslconfig は INI なので素通し（JSON バリデータに掛けてはいけない）
target_kind() {
  case "$1" in
    wslconfig) printf 'raw' ;;
    terminal) printf 'json' ;;
  esac
}

target_note() {
  case "$1" in
    wslconfig) printf '反映には `wsl --shutdown` が必要です。' ;;
    terminal) printf '反映には Windows Terminal の再起動が必要です。' ;;
  esac
}

# 正規化した内容を stdout に出す。読めない・壊れているなら非ゼロ。
# 壊れた設定を反対側へ伝播させないための門番
read_normalized() {
  local target="$1" path="$2" label="$3"
  if [[ -z "$path" ]]; then
    echo "ERROR: $label のパスを解決できません（$target）" >&2
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "ERROR: $label が見つかりません: $path" >&2
    return 1
  fi
  if [[ "$(target_kind "$target")" == "json" ]]; then
    if ! jq -S . "$path" 2>/dev/null; then
      echo "ERROR: $label が正しいJSONではありません: $path" >&2
      return 1
    fi
  else
    cat "$path"
  fi
}

one_pull() {
  local target="$1" dry_run="$2" live repo content
  live=$(target_live "$target")
  repo=$(target_repo "$target")

  content=$(read_normalized "$target" "$live" "実ファイル") || return 1

  settings_sync_reconcile_pull "$content" "$repo" "$dry_run" \
    "変更なし [$target]: リポジトリは実ファイルと一致しています" \
    "更新あり [$target]（--dry-run のため書き込みません）: $repo" \
    "更新 [$target]: $repo に実ファイルの内容を取り込みました"
}

one_push() {
  local target="$1" force="$2" live repo content live_content
  live=$(target_live "$target")
  repo=$(target_repo "$target")

  content=$(read_normalized "$target" "$repo" "リポジトリ版") || return 1

  if [[ -z "$live" ]]; then
    echo "ERROR: 実ファイルのパスを解決できません（$target）" >&2
    return 1
  fi

  if [[ ! -f "$live" ]]; then
    settings_sync_write_if_changed "$content" "$live"
    echo "作成 [$target]: $live をリポジトリ版から作成しました。$(target_note "$target")"
    return 0
  fi

  live_content=$(read_normalized "$target" "$live" "実ファイル") || {
    # 実ファイルが壊れている場合は --force でのみ復旧させる
    if [[ "$force" -eq 1 ]]; then
      settings_sync_write_if_changed "$content" "$live"
      echo "上書き [$target]: 壊れた $live をリポジトリ版で復旧しました。$(target_note "$target")"
      return 0
    fi
    return 1
  }

  local reject_header
  reject_header=$(
    cat <<EOF
ERROR: 実ファイルとリポジトリに差分があるため push しません（$target）。
  実ファイル: $live
  リポジトリ: $repo

実ファイル側の変更を残すなら pull を、
リポジトリ側で上書きしてよいなら push --force を実行してください。
差分（左: リポジトリ / 右: 実ファイル）:
EOF
  )

  settings_sync_reconcile_push "$content" "$live_content" "$force" "$content" "$live" \
    "$reject_header" \
    "変更なし [$target]: 実ファイルはリポジトリと一致しています" \
    "上書き [$target]: $live をリポジトリ版で上書きしました。$(target_note "$target")"
}

one_status() {
  local target="$1" live repo live_content repo_content
  live=$(target_live "$target")
  repo=$(target_repo "$target")

  live_content=$(read_normalized "$target" "$live" "実ファイル") || return 1
  repo_content=$(read_normalized "$target" "$repo" "リポジトリ版") || return 1

  settings_sync_reconcile_status "$repo_content" "$live_content" \
    "一致 [$target]: 実ファイルとリポジトリは同じ内容です" \
    "差分あり [$target]（左: リポジトリ / 右: 実ファイル）"
}

main() {
  local action="${1:-}"
  shift || true

  local target="" dry_run=0 force=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --force) force=1 ;;
      -h | --help)
        usage
        return 0
        ;;
      -*)
        echo "ERROR: 不明なオプション: $arg" >&2
        usage
        return 1
        ;;
      *)
        target="$arg"
        ;;
    esac
  done

  local selected=("${TARGETS[@]}")
  if [[ -n "$target" ]]; then
    local found=0 t
    for t in "${TARGETS[@]}"; do
      [[ "$t" == "$target" ]] && found=1
    done
    if [[ "$found" -eq 0 ]]; then
      echo "ERROR: 不明な target: $target（指定できるのは ${TARGETS[*]}）" >&2
      return 1
    fi
    selected=("$target")
  fi

  local rc=0 t
  for t in "${selected[@]}"; do
    case "$action" in
      pull) one_pull "$t" "$dry_run" || rc=1 ;;
      push) one_push "$t" "$force" || rc=1 ;;
      status) one_status "$t" || rc=1 ;;
      *)
        usage
        return 1
        ;;
    esac
  done
  return "$rc"
}

main "$@"
