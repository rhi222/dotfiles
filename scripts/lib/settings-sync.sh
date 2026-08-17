#!/bin/bash
# 設定ファイルのコピー同期（pull/push/status）で使う共通ロジック。
#
# sync-claude-settings.sh と sync-windows-settings.sh はどちらも「実ファイルを正とし、
# リポジトリがそれを追いかける」コピー同期で、pull/push/status の制御フロー
# （差分チェック → dry-run → force 拒否 → 書き込み）がほぼ同じだった。その骨格を
# ここに集約する。
#
# 各スクリプト固有の部分（LIVE/REPO のパス解決・機密マスク・JSON/INI の正規化・
# メッセージ文言）は呼び出し側が持ち、ここには「正規化済みの内容」と「表示する文言」
# を渡す。壊れた設定を弾く門番（read_normalized）や push --force の拒否判定といった
# 安全弁は、呼び出し側とこのファイルで役割を分担して保つ。
#
# このファイルは source される前提なので set -e は張らない（呼び出し側の set -uo
# pipefail に従う）。単体テストは test-sync-claude-settings.sh /
# test-sync-windows-settings.sh が兼ねる。

# $1 の内容を $2 に書く。既に同一内容なら書かない（0=書いた, 1=変更なし）。
#
# 書き込みは同ディレクトリの一時ファイル + rename でアトミックに行う。途中で
# 中断されても書きかけの settings.json が残らないようにするため。既存ファイルの
# パーミッションは引き継ぐ（~/.claude/settings.json の 600 を崩さない）。新規作成時は
# リダイレクト（`> file`）と同じく umask に従う。
settings_sync_write_if_changed() {
  local content="$1" dest="$2"
  if [[ -f "$dest" ]] && printf '%s\n' "$content" | diff -q - "$dest" >/dev/null 2>&1; then
    return 1
  fi

  local dir
  dir=$(dirname "$dest")
  mkdir -p "$dir"

  local tmp
  tmp=$(mktemp "$dir/.settings-sync.XXXXXX") || return 1

  if ! printf '%s\n' "$content" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  # mktemp は 600 で作るので、リダイレクト時の見え方に合わせて権限を整える。
  if [[ -f "$dest" ]]; then
    chmod --reference="$dest" "$tmp" 2>/dev/null || true
  else
    chmod "$(printf '%03o' "$((0666 & ~0$(umask)))")" "$tmp" 2>/dev/null || true
  fi

  if ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  return 0
}

# pull（実ファイル -> リポジトリ）の共通末尾。正規化・マスク済みの $content を $dest に
# 反映する。差分が無ければ書かず、$dry_run のときは書かずに差分だけ出す。
# 文言は呼び出し側が組み立てて渡す（[$target] 前置などの差異を吸収するため）。
settings_sync_reconcile_pull() {
  local content="$1" dest="$2" dry_run="$3"
  local msg_unchanged="$4" msg_dryrun="$5" msg_updated="$6"

  if [[ -f "$dest" ]] && printf '%s\n' "$content" | diff -q - "$dest" >/dev/null 2>&1; then
    echo "$msg_unchanged"
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    echo "$msg_dryrun"
    [[ -f "$dest" ]] && diff <(cat "$dest") <(printf '%s\n' "$content") || true
    return 0
  fi

  settings_sync_write_if_changed "$content" "$dest"
  echo "$msg_updated"
}

# push（リポジトリ -> 実ファイル）のうち、実ファイルが存在し JSON も壊れていない
# 通常経路の共通末尾。実ファイルが無い場合・壊れている場合の分岐は、文言と扱いが
# 個別なので呼び出し側に残す。
#
#   $repo_content   比較の基準になるリポジトリ側の内容
#   $live_cmp       比較の基準になる実ファイル側の内容（claude はマスク後）
#   $force          --force なら 1
#   $write_content  上書き時に実際に書き出す内容（claude は機密マージ後）
#   $dest           実ファイルのパス
#   $reject_header  --force なしで差分があるときに stderr へ出す案内文（末尾の差分見出しまで）
#
# --force なしで差分があれば書き込まず 1 を返す（安全弁）。
settings_sync_reconcile_push() {
  local repo_content="$1" live_cmp="$2" force="$3" write_content="$4" dest="$5"
  local reject_header="$6" msg_unchanged="$7" msg_overwrite="$8"

  if [[ "$repo_content" == "$live_cmp" ]]; then
    echo "$msg_unchanged"
    return 0
  fi

  if [[ "$force" -eq 0 ]]; then
    printf '%s\n' "$reject_header" >&2
    diff <(printf '%s\n' "$repo_content") <(printf '%s\n' "$live_cmp") >&2 || true
    return 1
  fi

  settings_sync_write_if_changed "$write_content" "$dest"
  echo "$msg_overwrite"
}

# status の共通末尾。どちらも書き換えず、差分の有無だけを報告する。
settings_sync_reconcile_status() {
  local repo_content="$1" live_cmp="$2" msg_match="$3" msg_diff_header="$4"

  if [[ "$live_cmp" == "$repo_content" ]]; then
    echo "$msg_match"
    return 0
  fi

  echo "$msg_diff_header"
  diff <(printf '%s\n' "$repo_content") <(printf '%s\n' "$live_cmp") || true
}
