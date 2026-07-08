#!/bin/bash
# npm / pip グローバルパッケージ更新の共通ロジック。
# daily-update.sh から source して使う。source 側の set オプションを尊重する
# ため、このファイル自体では set -e を宣言しない。
#
# 公開関数:
#   npm_global_update / pip_global_update  … 更新のエントリポイント
#   npm_select_targets / pip_select_targets … 更新対象の選定（純粋関数）
#   read_package_list / report_pkg_diff / pkg_install_with_diff … 共通部品

# パッケージ宣言ファイルを読み、コメント行・行内コメント・空白・空行を
# 除去して1行1エントリで出力する。
# Args: <file>
read_package_list() {
  awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]#.*$/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print }
  ' "$1"
}

# Tab-separated "name<TAB>version" snapshot of currently installed global
# npm packages, sorted for deterministic diffing.
list_npm_globals() {
  npm list -g --depth=0 --json 2>/dev/null |
    jq -r '.dependencies // {} | to_entries[] | "\(.key)\t\(.value.version // "?")"' |
    sort
}

list_pip_globals() {
  pip list --format=json 2>/dev/null |
    jq -r '.[] | "\(.name | ascii_downcase)\t\(.version)"' |
    sort
}

# Compare two snapshot files and print a human-friendly summary of upgrades
# and newly-installed packages.
report_pkg_diff() {
  awk -F'\t' '
    NR==FNR { before[$1] = $2; next }
    {
      if (!($1 in before)) {
        added = added sprintf("  %s %s (new)\n", $1, $2); na++
      } else if (before[$1] != $2) {
        upgraded = upgraded sprintf("  %s %s → %s\n", $1, before[$1], $2); nu++
      }
    }
    END {
      if (nu > 0) printf "Upgraded %d package(s):\n%s", nu, upgraded
      if (na > 0) printf "Installed %d new package(s):\n%s", na, added
      if (nu == 0 && na == 0) print "No package changes."
    }
  ' "$1" "$2"
}

# インストール前後のスナップショット差分を報告しつつインストールを実行する。
# install_fn が失敗しても diff 報告と一時ファイル掃除まで必ず到達し、
# その rc を返す（set -e の有無に依存しない）。
# Args: <list_fn> <install_fn> <target...>
pkg_install_with_diff() {
  local list_fn="$1" install_fn="$2"
  shift 2

  local before_file after_file rc=0
  before_file=$(mktemp)
  after_file=$(mktemp)

  "$list_fn" >"$before_file"
  if "$install_fn" "$@" >/dev/null; then rc=0; else rc=$?; fi
  "$list_fn" >"$after_file"

  report_pkg_diff "$before_file" "$after_file"
  rm -f "$before_file" "$after_file"
  return "$rc"
}

# Decide which managed npm globals actually need (re)installing. A package is
# a target when it is either flagged by `npm outdated` (a newer version exists)
# or not currently installed at all (newly added to the list — `npm outdated`
# never reports missing packages). Pure function: all inputs are arguments, so
# it is unit-testable without touching the network.
#
# Args: <outdated_json> <installed_names> <name...>
#   outdated_json  : `npm outdated -g --json` output (empty string ok)
#   installed_names: newline-separated names of currently-installed globals
# Prints one "<name>@latest" per target, newline-separated.
npm_select_targets() {
  local outdated_json="$1"
  local installed="$2"
  shift 2
  [ -n "$outdated_json" ] || outdated_json='{}'

  local n
  for n in "$@"; do
    if jq -e --arg n "$n" 'has($n)' <<<"$outdated_json" >/dev/null 2>&1; then
      printf '%s@latest\n' "$n"
    elif ! grep -qxF -- "$n" <<<"$installed"; then
      printf '%s@latest\n' "$n"
    fi
  done
}

npm_install_globals() {
  npm install -g --no-audit --no-fund "$@"
}

# Update global npm packages listed in .default-npm-packages to @latest.
# `mise upgrade` only bumps language runtimes; npm globals installed via
# mise's default-npm-packages hook are not touched after first install.
#
# `npm install -g pkg@latest` re-resolves and reinstalls the full dependency
# tree unconditionally — slow even when nothing changed. Instead, a fast,
# metadata-only `npm outdated -g` check (~1s, no tree resolution/download)
# narrows the install to only the packages that actually moved.
npm_global_update() {
  local file="$HOME/.config/mise/.default-npm-packages"
  if [ ! -f "$file" ]; then
    echo "Skip: $file not found"
    return 0
  fi

  local names
  mapfile -t names < <(read_package_list "$file")

  if [ "${#names[@]}" -eq 0 ]; then
    echo "No packages to update."
    return 0
  fi

  # `npm outdated` exits 1 when anything is outdated, so guard with `|| true`.
  local outdated_json installed
  outdated_json=$(npm outdated -g --json 2>/dev/null || true)
  installed=$(npm list -g --depth=0 --json 2>/dev/null |
    jq -r '.dependencies // {} | keys[]')

  local targets
  mapfile -t targets < <(npm_select_targets "$outdated_json" "$installed" "${names[@]}")

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No package changes."
    return 0
  fi

  pkg_install_with_diff list_npm_globals npm_install_globals "${targets[@]}"
}

# PEP 503 name normalizer (stream filter): lowercase and collapse runs of
# -, _, . to a single -, so e.g. typing_extensions and typing-extensions match.
_pip_normalize() {
  tr '[:upper:]' '[:lower:]' | sed -E 's/[-_.]+/-/g'
}

# Decide which managed pip packages need (re)installing. A spec is a target
# when its base name (extras like [all] stripped) is flagged by
# `pip list --outdated` or is not currently installed. Names are compared
# PEP 503-normalized. The original spec (extras kept) is what gets printed so
# `pip install -U python-lsp-server[all]` keeps its extras. Pure/unit-testable.
#
# Args: <outdated_json> <installed_names> <spec...>
#   outdated_json  : `pip list --outdated --format=json` output (empty ok)
#   installed_names: newline-separated names of currently-installed packages
# Prints the original specs that need installing, newline-separated.
pip_select_targets() {
  local outdated_json="$1"
  local installed="$2"
  shift 2
  [ -n "$outdated_json" ] || outdated_json='[]'

  local outdated_norm installed_norm
  outdated_norm=$(jq -r '.[].name' <<<"$outdated_json" 2>/dev/null | _pip_normalize)
  installed_norm=$(_pip_normalize <<<"$installed")

  local spec base base_norm
  for spec in "$@"; do
    base=$(printf '%s' "$spec" | sed 's/\[.*//') # strip extras: foo[all] -> foo
    base_norm=$(_pip_normalize <<<"$base")
    if grep -qxF -- "$base_norm" <<<"$outdated_norm"; then
      printf '%s\n' "$spec"
    elif ! grep -qxF -- "$base_norm" <<<"$installed_norm"; then
      printf '%s\n' "$spec"
    fi
  done
}

pip_install_upgrade() {
  pip install -U "$@"
}

# Same idea as npm for pip globals listed in .default-python-packages.
# A fast, metadata-only `pip list --outdated` check narrows the reinstall to
# packages that moved or are missing. pip's default only-if-needed upgrade
# strategy means an already-latest top-level package is a no-op anyway, so
# skipping it is behavior-preserving.
pip_global_update() {
  local file="$HOME/.config/mise/.default-python-packages"
  if [ ! -f "$file" ]; then
    echo "Skip: $file not found"
    return 0
  fi

  local packages
  mapfile -t packages < <(read_package_list "$file")

  if [ "${#packages[@]}" -eq 0 ]; then
    echo "No packages to update."
    return 0
  fi

  local outdated_json installed
  outdated_json=$(pip list --outdated --format=json 2>/dev/null || true)
  installed=$(pip list --format=json 2>/dev/null | jq -r '.[].name')

  local targets
  mapfile -t targets < <(pip_select_targets "$outdated_json" "$installed" "${packages[@]}")

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No package changes."
    return 0
  fi

  pkg_install_with_diff list_pip_globals pip_install_upgrade "${targets[@]}"
}
