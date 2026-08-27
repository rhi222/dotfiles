#!/bin/bash
# 公開入口をfeature別に整理し、internalとの境界を維持する。
# scripts・internal・testsで同じfeature名を使い、互換旧名はmanifestだけに置く。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

pass=0
fail=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $name"
    pass=$((pass + 1))
  else
    echo "NG: $name"
    fail=$((fail + 1))
  fi
}

check "旧domainsディレクトリが無い" test ! -e "$REPO_ROOT/domains"
check "internalの配置規約がある" test -f "$REPO_ROOT/internal/README.md"
check "dotfilesLinkの公開入口を維持する" test -x "$REPO_ROOT/dotfilesLink.sh"
check "bootstrapの公開入口を維持する" test -x "$REPO_ROOT/scripts/setup/bootstrap.sh"
check "dotfilesLink実装はinternal/linkにある" test -f "$REPO_ROOT/internal/link/reconcile.sh"
check "bootstrap実装はinternal/bootstrapにある" test -f "$REPO_ROOT/internal/bootstrap/setup.sh"
check "Linear実装はinternalにある" test -f "$REPO_ROOT/internal/linear/lib/api.sh"
check "日報実装はinternalにある" test -f "$REPO_ROOT/internal/nippo/lib/paths.sh"

# ref-checkが削除済みpathのliteralを参照と誤認しないよう、名前は変数で組み立てる。
check "cron共通実装はscripts/libへ戻さない" \
  test ! -e "$REPO_ROOT/scripts/lib/${CRON_LIB:-cron-claude}.sh"
check "session共通実装はscripts/libへ戻さない" \
  test ! -e "$REPO_ROOT/scripts/lib/${SESSION_LIB:-herdr-restore}.sh"
check "update共通実装はscripts/libへ戻さない" \
  test ! -e "$REPO_ROOT/scripts/lib/${UPDATE_LIB:-pkg-update}.sh"

check "scripts直下はdotctl bootstrap以外の実行scriptを置かない" \
  test -z "$(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' ! -name 'setup-dotctl.sh' -print -quit)"
check "旧dotctlが使うbootstrap pathを維持する" \
  test -x "$REPO_ROOT/scripts/setup-dotctl.sh"
check "公開入口をfeature別に置く" \
  test -x "$REPO_ROOT/scripts/worktree/init.sh"
check "互換pathのmanifestがある" \
  test -f "$REPO_ROOT/scripts/compat-links.txt"

compat_targets_exist() {
  local old target
  while IFS="|" read -r old target; do
    [[ -n "$old" ]] || continue
    [[ "$old" == "#"* ]] && continue
    [ -e "$REPO_ROOT/scripts/$target" ] || return 1
  done <"$REPO_ROOT/scripts/compat-links.txt"
}
check "互換manifestの正規pathがすべて存在する" compat_targets_exist

compat_shell_paths_resolve() {
  local old target script
  while IFS="|" read -r old target; do
    [[ -n "$old" ]] || continue
    [[ "$old" == "#"* ]] && continue
    [[ "$target" == *.sh ]] || continue
    script="$REPO_ROOT/scripts/$target"
    if grep -q 'SCRIPT_DIR=' "$script"; then
      grep -q 'readlink -f' "$script" || return 1
    fi
  done <"$REPO_ROOT/scripts/compat-links.txt"
}
check "互換shell入口はsymlinkの実体を基準にpathを解決する" \
  compat_shell_paths_resolve

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
