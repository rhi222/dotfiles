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

# shellcheck source=../../internal/update/fisher.sh
source "$SCRIPT_DIR/../../internal/update/fisher.sh"

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

# dotctl の再ビルド。**git pull 後に再ビルドしないと、cron と hook は古い
# バイナリを黙って実行し続ける**（このスクリプト自身が古い installs/<tool>/ の
# gh を掴んで gh skill を失った事故と同型）。日次で追随させる。
#
# go が無い端末と go.mod が無いリポジトリでは何もせず成功扱いにする。
# 更新対象も更新手段も無い端末で毎日 FAILED 通知が飛ぶだけになるため
# （yazi の package.toml と同じ扱い）。あとから mise で go を入れれば
# このステップは自動で効き始める。
#
# 一方 **ビルドの失敗は隠さない。** 古いバイナリを掴み続ける状態そのものなので、
# run_step で FAILED として拾わせる。dotctl 自身も実行のたびに repo HEAD との
# ずれを警告するが、そちらは「気付ける」だけで直しはしない。
DOTCTL_GO_MOD="${DOTCTL_GO_MOD:-$SCRIPT_DIR/../../go.mod}"
DOTCTL_SETUP_SCRIPT="${DOTCTL_SETUP_SCRIPT:-$SCRIPT_DIR/../setup/dotctl.sh}"
DOTCTL_GO_BIN="${DOTCTL_GO_BIN:-go}"

dotctl_rebuild() {
  if [ ! -f "$DOTCTL_GO_MOD" ]; then
    echo "no go.mod at $DOTCTL_GO_MOD, skipping"
    return 0
  fi
  # **PATH を削って「go が無い」を作れない。** CI の runner は /usr/bin:/bin にも
  # go を持っており、それで CI だけ落ちた。DOTCTL_GO_BIN に存在しない名前を渡す
  if ! command -v "$DOTCTL_GO_BIN" >/dev/null 2>&1; then
    echo "go not found, skipping (mise install go)"
    return 0
  fi
  bash "$DOTCTL_SETUP_SCRIPT"
}

yazi_pkg_upgrade() {
  if [ ! -f "$YAZI_PACKAGE_FILE" ]; then
    echo "no package.toml at $YAZI_PACKAGE_FILE, skipping"
    return 0
  fi
  if ! command -v dotctl >/dev/null 2>&1; then
    echo "dotctl not found, running ya pkg upgrade without update check"
    ya pkg upgrade
    return
  fi
  dotctl yazi-update
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
WORKTREE_CLEANUP_SCRIPT="${WORKTREE_CLEANUP_SCRIPT:-$SCRIPT_DIR/../worktree/cleanup.sh}"

worktree_cleanup_check() {
  local script="$WORKTREE_CLEANUP_SCRIPT"
  if [ ! -f "$script" ]; then
    echo "worktree-cleanup.sh が無いためスキップ: $script"
    return 0
  fi

  local out count
  out=$(bash "$script" 2>&1)
  # daily-update の `=== step ===` と cleanup 内部の `== section ==` を
  # 同じ左端に並べると階層が潰れる。単独実行時の cleanup の体裁は変えず、
  # 埋め込むここだけ2スペース字下げして子コマンドの出力だと分かるようにする。
  printf '%s\n' "$out" | sed 's/^/  /'

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
      # shellcheck source=../lib/notify-windows-toast.sh
      source "$SCRIPT_DIR/../lib/notify-windows-toast.sh"
      send_windows_toast "worktree の消し忘れ" \
        "削除候補が $count 件あります。bash scripts/worktree/cleanup.sh で確認してください。" || true
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
  ' "$SCRIPT_DIR/../setup/claude-skills.txt")

  if [ "${#names[@]}" -eq 0 ]; then
    echo "No remote-managed skills to update."
    return 0
  fi

  gh skill update --all "${names[@]}" </dev/null
}

# vendored skill の upstream に更新が来ていないかを見る。**ファイルは触らない。**
#
# 実体は symlink で ~/.claude/skills へ生で繋がるので、作業ツリーを書き換えた
# 瞬間に有効になる。だからここは検知だけにして、取込は人が
# `skill-vendor.sh update <name> [name...]` を叩く。未レビューのコードが有効になる瞬間を
# 作らないため。
#
# 比較するのは upstream リポジトリの HEAD なので、その skill と無関係な commit でも
# 「更新あり」になる。skill-vendor.sh update 側が実ファイルの diff を取り、
# 変更が無ければ「変更なし」と言って commit だけ進めるので、ここは粗い信号でよい。
vendored_skill_check() {
  local vendor_dir="${SKILL_VENDOR_DIR:-$SCRIPT_DIR/../../.config/agents/skills-vendor}"
  if [ ! -d "$vendor_dir" ]; then
    echo "vendored skill はありません"
    return 0
  fi

  local found=0 behind=0 d name json origin commit remote
  local -a behind_names=()
  for d in "$vendor_dir"/*/; do
    [ -d "$d" ] || continue
    found=1
    name="$(basename "$d")"
    json="$d/.vendor.json"
    if [ ! -f "$json" ]; then
      echo "  $name: .vendor.json が無い"
      continue
    fi
    origin="$(jq -r .origin "$json")"
    commit="$(jq -r .commit "$json")"
    remote="$(git ls-remote "$origin" HEAD 2>/dev/null | awk '{print $1}')"
    if [ -z "$remote" ]; then
      echo "  $name: upstream を確認できません（$origin）"
      continue
    fi
    if [ "$remote" != "$commit" ]; then
      behind=$((behind + 1))
      behind_names+=("$name")
      echo "  $name: upstream に更新あり（${commit:0:7} -> ${remote:0:7}）"
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "vendored skill はありません"
  elif [ "$behind" -eq 0 ]; then
    echo "全 vendored skill が upstream と同じ commit です"
  else
    printf '  一括取込: bash scripts/skills/vendor.sh update'
    printf ' %q' "${behind_names[@]}"
    printf '\n'
  fi
  return 0
}

# 失敗があればWindowsトースト通知を出す。WSL2以外（powershell.exeが無い環境）
# ではスキップ。通知自体の失敗で全体を落とさない。
notify_failures() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  # shellcheck source=../lib/notify-windows-toast.sh
  source "$SCRIPT_DIR/../lib/notify-windows-toast.sh"
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
  # 以降の更新判定（fisher cacheを含む）が現在のdotctl実装を使えるよう、
  # Go更新後すぐに再ビルドする。
  run_step "dotctl rebuild" dotctl_rebuild
  run_step "nvim Lazy update" timeout 300 nvim --headless -c "luafile $SCRIPT_DIR/../setup/nvim-lazy-update.lua" +qa
  run_step "nvim Mason update" timeout 300 nvim --headless -c 'autocmd User MasonUpdateAllComplete quitall' -c 'MasonUpdateAll'
  # New skills are added via `scripts/skills/add.sh`; bootstrap uses
  # `setup-claude-skills.sh`. Daily only runs the update step.
  run_step "gh skill update" gh_skill_update
  # 同様に、拡張の追加は gh-extensions.txt + setup-gh-extensions.sh。
  # ここは既存拡張の更新だけを回す（--pin 済みの拡張は据え置かれる）。
  run_step "gh extension upgrade" gh extension upgrade --all
  # yazi プラグインも同様に、宣言済みのものの更新だけを回す。
  run_step "yazi pkg upgrade" yazi_pkg_upgrade
  # fish プラグイン（tide / fzf.fish）も同様。ここが無かったため、この2つだけ
  # どの端末でも手動でしか更新されていなかった。
  run_step "fisher update" fisher_update
  # 消し忘れ worktree の検知。情報提供なので run_step_soft を使い、
  # gh 未認証などで daily-update 全体を FAILED にしない。
  run_step_soft "worktree cleanup check" worktree_cleanup_check
  # vendored skill の更新検知。取込はしない（未レビューのコードが有効になる
  # 瞬間を作らないため）。ネットワーク断で全体を FAILED にしないので soft。
  run_step_soft "vendored skill 更新チェック" vendored_skill_check
  # Claude Code が実行時に書き換えた settings.json をリポジトリに取り込む。
  # 作業ツリーに差分が出るだけなので、コミットするかは人間が判断する。
  run_step "claude settings pull" bash "$SCRIPT_DIR/../settings/sync-claude.sh" pull

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
