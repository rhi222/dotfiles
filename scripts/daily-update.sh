#!/bin/bash
set -euo pipefail

# mise-managed tools (gh, nvim, cargo, ...) must resolve via shims, not via
# the version-locked PATH inherited from a long-running parent shell. After
# `mise upgrade` bumps a tool, the old `installs/<tool>/<ver>/...` path
# becomes stale; for `gh` that means falling through to /usr/bin/gh 2.74.0,
# which lacks the `skill` subcommand and breaks `gh skill update`.
export PATH="$HOME/.local/share/mise/shims:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.local/state/daily-update"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"
# 日次ログは溜まり続けるので、30日より古いものを起動時に掃除する
find "$LOG_DIR" -name '*.log' -mtime +30 -delete 2>/dev/null || true

# shellcheck source=lib/pkg-update.sh
source "$SCRIPT_DIR/lib/pkg-update.sh"

failures=()

run_step() {
  local name="$1"
  shift
  echo "=== $name ===" | tee -a "$LOG_FILE"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo "=== $name: OK ===" | tee -a "$LOG_FILE"
  else
    echo "=== $name: FAILED ===" | tee -a "$LOG_FILE"
    failures+=("$name")
  fi
  echo "" | tee -a "$LOG_FILE"
}

# worktree掃除の候補チェックのように「情報提供」であって「更新」ではないステップ用。
# 失敗しても failures には積まず、daily-update 全体を FAILED にしない。
# gh 未認証やネットワーク断で毎日 FAILED 通知が飛ぶのを避けるため。
run_step_soft() {
  local name="$1"
  shift
  echo "=== $name ===" | tee -a "$LOG_FILE"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo "=== $name: OK ===" | tee -a "$LOG_FILE"
  else
    echo "=== $name: 失敗（全体は継続） ===" | tee -a "$LOG_FILE"
  fi
  echo "" | tee -a "$LOG_FILE"
}

# yazi のプラグイン更新。パッケージの追加は package.toml + setup-yazi-plugins.sh の
# 担当で、ここは宣言済みパッケージの更新だけを回す。
#
# `ya pkg upgrade` は package.toml の rev/hash を書き換える。この実体はリポジトリ内に
# あるので作業ツリーに差分が出るが、コミットするかは claude settings pull と同じく人間が判断する。
#
# package.toml が無い端末（yazi 未導入）では何もせず成功扱いにする。毎日 FAILED 通知が
# 飛ぶと無視されるようになるため。テストから差し替えられるようにパスを変数に持つ。
YAZI_PACKAGE_FILE="${YAZI_PACKAGE_FILE:-$HOME/.config/yazi/package.toml}"

yazi_pkg_upgrade() {
  if [ ! -f "$YAZI_PACKAGE_FILE" ]; then
    echo "no package.toml at $YAZI_PACKAGE_FILE, skipping"
    return 0
  fi
  ya pkg upgrade
}

# cargo でインストールしたバイナリの更新。`cargo install-update` は cargo 本体では
# なく cargo-update crate が提供するサブコマンドで、リポジトリのどこにも宣言が無い。
#
# 提供コマンドが無ければ何もせず成功扱いにする。`cargo install` 由来のバイナリが
# 1つも無い端末では更新対象も更新手段も無く、毎日 FAILED 通知が飛ぶだけになるため
# （yazi の package.toml と同じ扱い）。あとから `cargo install cargo-update` すれば
# このステップは自動で効き始める。
#
# 検出は `command -v` で行う。cargo は cargo-<sub> という名前のバイナリを
# PATH と $CARGO_HOME/bin から引くので、`~/.cargo/bin` が PATH にあることが前提。
# 外れていた場合は「更新をスキップする」側に倒れるので、壊れる方向には転ばない。
cargo_install_update() {
  if ! command -v cargo-install-update >/dev/null 2>&1; then
    echo "cargo-update not installed, skipping"
    return 0
  fi
  cargo install-update -a
}

# 消し忘れ worktree の溜まり込みを検知する。dry-run で候補を数えるだけで、削除はしない。
# 候補が閾値以上のときだけトースト通知する（毎日通知が飛ぶと無視されるようになるため）。
WORKTREE_CLEANUP_NOTIFY_THRESHOLD="${WORKTREE_CLEANUP_NOTIFY_THRESHOLD:-5}"

# 掃除スクリプトの場所。テストから偽スクリプトに差し替えるために上書きできる。
# SCRIPT_DIR 自体を差し替えると lib/notify-windows-toast.sh も引けなくなるため、
# 掃除スクリプトのパスだけを独立した変数にしている。
WORKTREE_CLEANUP_SCRIPT="${WORKTREE_CLEANUP_SCRIPT:-$SCRIPT_DIR/worktree-cleanup.sh}"

worktree_cleanup_check() {
  local script="$WORKTREE_CLEANUP_SCRIPT"
  if [ ! -f "$script" ]; then
    echo "worktree-cleanup.sh が無いためスキップ: $script"
    return 0
  fi

  local out count
  out=$(bash "$script" 2>&1)
  echo "$out"

  # 表示行ではなく機械可読サマリ行から件数を取る（表示の体裁変更で壊れないように）。
  # `^worktree-cleanup:` で行頭アンカーする。dry-run ではこの行の後ろに人間向けの
  # 案内が出るため最終行ではなく、`tail -1` では取れない。
  count=$(printf '%s\n' "$out" |
    grep '^worktree-cleanup:' |
    sed -n 's/.*DELETE_CANDIDATES=\([0-9]\{1,\}\).*/\1/p' |
    head -1)
  count="${count:-0}"
  echo "worktree掃除の候補: $count 件（通知閾値 $WORKTREE_CLEANUP_NOTIFY_THRESHOLD 件）"

  if [ "$count" -ge "$WORKTREE_CLEANUP_NOTIFY_THRESHOLD" ]; then
    if command -v powershell.exe >/dev/null 2>&1; then
      # shellcheck source=lib/notify-windows-toast.sh
      source "$SCRIPT_DIR/lib/notify-windows-toast.sh"
      send_windows_toast "worktree の消し忘れ" \
        "削除候補が $count 件あります。bash scripts/worktree-cleanup.sh で確認してください。" || true
    fi
  fi
  return 0
}

# Only update skills managed via `gh skill install` (remote lines in
# claude-skills.txt). Local-cloned or system skills lack GitHub metadata
# and would trigger noisy "Reinstall to enable updates" warnings.
gh_skill_update() {
  local names
  mapfile -t names < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ || /^[[:space:]]*local:/ { next }
    { sub(/[[:space:]]#.*$/, ""); split($2, a, "@"); n = a[1]; sub(/.*\//, "", n); if (n != "") print n }
  ' "$SCRIPT_DIR/claude-skills.txt")

  if [ "${#names[@]}" -eq 0 ]; then
    echo "No remote-managed skills to update."
    return 0
  fi

  gh skill update --all "${names[@]}" </dev/null
}

# 失敗があればWindowsトースト通知を出す。WSL2以外（powershell.exeが無い環境）
# ではスキップ。通知自体の失敗で全体を落とさない。
notify_failures() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  # shellcheck source=lib/notify-windows-toast.sh
  source "$SCRIPT_DIR/lib/notify-windows-toast.sh"
  send_windows_toast "daily-update 失敗" "FAILED: ${failures[*]}" || true
}

main() {
  run_step "apt update" sudo apt-get update -qq
  run_step "apt upgrade" sudo apt-get upgrade -y -qq
  run_step "cargo install-update" cargo_install_update
  run_step "mise self-update" mise self-update -y
  run_step "mise upgrade" mise upgrade
  # upgrade で最新でなくなった版を同一実行内で掃除する（tracked 設定から
  # 参照されなくなったツール版を実削除。確認プロンプトなし）
  run_step "mise prune" mise prune
  run_step "npm global update" npm_global_update
  run_step "pip global update" pip_global_update
  run_step "nvim Lazy update" timeout 300 nvim --headless -c "luafile $SCRIPT_DIR/nvim-lazy-update.lua" +qa
  run_step "nvim Mason update" timeout 300 nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'
  # New skills are added via `scripts/skill-add.sh`; bootstrap uses
  # `setup-claude-skills.sh`. Daily only runs the update step.
  run_step "gh skill update" gh_skill_update
  # 同様に、拡張の追加は gh-extensions.txt + setup-gh-extensions.sh。
  # ここは既存拡張の更新だけを回す（--pin 済みの拡張は据え置かれる）。
  run_step "gh extension upgrade" gh extension upgrade --all
  # yazi プラグインも同様に、宣言済みのものの更新だけを回す。
  run_step "yazi pkg upgrade" yazi_pkg_upgrade
  # 消し忘れ worktree の検知。情報提供なので run_step_soft を使い、
  # gh 未認証などで daily-update 全体を FAILED にしない。
  run_step_soft "worktree cleanup check" worktree_cleanup_check
  # Claude Code が実行時に書き換えた settings.json をリポジトリに取り込む。
  # 作業ツリーに差分が出るだけなので、コミットするかは人間が判断する。
  run_step "claude settings pull" bash "$SCRIPT_DIR/sync-claude-settings.sh" pull

  echo "========================================" | tee -a "$LOG_FILE"
  if [ ${#failures[@]} -gt 0 ]; then
    echo "FAILED: ${failures[*]}" | tee -a "$LOG_FILE"
    notify_failures
    exit 1
  else
    echo "All updates completed successfully." | tee -a "$LOG_FILE"
  fi
}

# Only run the update pipeline when executed directly; sourcing (e.g. from
# test-daily-update.sh) loads the functions without triggering any updates.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
