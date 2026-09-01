#!/bin/bash
# dclean のオプションが説明付きで補完されることを固定する。
# dclean は引数にファイルを取らないので、候補にファイル名を混ぜない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPLETION_DIR="$REPO_ROOT/.config/fish/my/completions"
FUNCTION_DIR="$REPO_ROOT/.config/fish/my/functions"
COMPLETION_FILE="$COMPLETION_DIR/dclean.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

# **fish は「そのコマンドが存在するとき」しか補完を autoload しない。**
# dclean は関数なので、config.fish と同じく function path も張らないと
# 補完ファイルを置いただけでは発火せず、テストが常に空を見る。
complete_for() {
  fish --no-config -c \
    "set -g fish_function_path '$FUNCTION_DIR' \$fish_function_path
     set -g fish_complete_path '$COMPLETION_DIR' \$fish_complete_path
     complete -C 'dclean $1'"
}

check "dclean の補完定義がある" test -f "$COMPLETION_FILE"

longs=$(complete_for -- | cut -f1 | sort)
expected=$(printf '%s\n' --all --help --refresh --status)
check "long option を全て補完する" test "$longs" = "$expected"

check "候補に説明を付ける" \
  test "$(complete_for -- | grep -c $'\t')" -eq 4

shorts=$(complete_for - | cut -f1 | sort)
check "short option も補完する" \
  test "$(printf '%s\n' "$shorts" | grep -cFx -e -a)" -eq 1

# **ファイル補完を混ぜない。** dclean はフラグしか取らないので、
# 引数位置でカレントのファイル名が並ぶと候補がノイズで埋まる。
bare=$(complete_for "")
check "引数位置でファイル候補を出さない" test -z "$bare"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
