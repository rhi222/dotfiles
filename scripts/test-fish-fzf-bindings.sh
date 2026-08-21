#!/bin/bash
# Ctrl+R / Ctrl+T を握るのが fzf.fish であることを固定するテスト
#
# 端末ごとに Ctrl+R の実装が入れ替わり、そのたび設定を寄せ替えて片側が壊れていた。
#   fzf.fish の _fzf_search_history  → `fzf_history_opts` が効く / 区切りは " │ "
#   fzf 標準統合の fzf-history-widget → `FZF_CTRL_R_OPTS` が効く / 区切りはタブ3列
# 分岐点は `fish_user_key_bindings` が `fzf --fish | source` するかどうかで、これは
# 昔の ~/.fzf/install が ~/.config/fish/functions/ に置いていく追跡外の実ファイル。
#
# そこで repo 側で `my/functions/fish_user_key_bindings.fish` を持ち、
# fish_function_path の先頭に居ることで追跡外の実ファイルを影にする。
# ここで検査するのはその2点（担当の固定と、担当に対応した変数を使っていること）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FISH_DIR="$(cd "$SCRIPT_DIR/../.config/fish" && pwd)"
FUNC_DIR="$FISH_DIR/my/functions"
CONF_FILE="$FISH_DIR/my/conf.d/10-fzf.fish"
UKB_FILE="$FUNC_DIR/fish_user_key_bindings.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         expected: $expected"
    echo "         actual  : $actual"
  fi
}

echo "== repo が fish_user_key_bindings を持つ =="

check "my/functions に定義がある" \
  "yes" \
  "$([[ -f "$UKB_FILE" ]] && echo yes || echo no)"

# 追跡外の実ファイルが `fzf --fish | source` していたのが原因なので、
# repo 側が同じことをしたら意味が無い。コメントで経緯を書いてあるため、
# 判定は行頭 `#` を落とした実コードに対して行う。
check "fzf 標準統合を呼ばない" \
  "no" \
  "$(sed -e 's/^[[:space:]]*#.*$//' "$UKB_FILE" 2>/dev/null |
    grep -q -- 'fzf .*--fish' && echo yes || echo no)"

echo "== config.fish の探索順で repo 側が勝つ =="

# config.fish が my/functions を先頭に足していること。ここが後ろに回ると
# ~/.config/fish/functions/ の追跡外ファイルに負ける。
check "config.fish が my/functions を先頭に prepend する" \
  "yes" \
  "$(grep -qE '^set -g fish_function_path ~/\.config/fish/my/functions \$fish_function_path$' \
    "$FISH_DIR/config.fish" && echo yes || echo no)"

# fish の autoload が本当に先頭優先か（この前提の上に上の prepend が乗っている）。
# 追跡外ファイルを模した定義を後ろに置き、repo 側が採られることを実 fish で見る。
STALE_DIR=$(mktemp -d)
trap 'rm -rf "$STALE_DIR"' EXIT
cat >"$STALE_DIR/fish_user_key_bindings.fish" <<'STALE'
function fish_user_key_bindings
    echo STALE_FZF_SHELL_INTEGRATION
end
STALE

resolved=$(fish --no-config -c \
  "set -g fish_function_path '$FUNC_DIR' '$STALE_DIR'; functions fish_user_key_bindings" 2>&1)

check "追跡外の fish_user_key_bindings を影にする" \
  "no" \
  "$(printf '%s' "$resolved" | grep -q 'STALE_FZF_SHELL_INTEGRATION' && echo yes || echo no)"

echo "== 履歴一覧の設定が fzf.fish 側の変数である =="

# 担当が fzf.fish なので、効くのは fzf_history_opts。
check "fzf_history_opts を設定している" \
  "yes" \
  "$(grep -qE '^set -g fzf_history_opts ' "$CONF_FILE" && echo yes || echo no)"

# FZF_CTRL_R_OPTS は fzf 標準統合しか読まない。これが復活していたら
# 「担当は fzf.fish」という前提と食い違っている（過去2回の往復がこれ）。
check "FZF_CTRL_R_OPTS は設定しない" \
  "no" \
  "$(grep -qE '^[^#]*set .*FZF_CTRL_R_OPTS' "$CONF_FILE" && echo yes || echo no)"

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
