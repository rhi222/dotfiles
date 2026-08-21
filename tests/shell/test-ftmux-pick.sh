#!/bin/bash
# __ftmux_pick_id のテスト。fzf を stub にして選択結果を固定する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"

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

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
if [[ ! -f "$FUNC_DIR/__ftmux_pick_id.fish" ]]; then
  echo "ERROR: $FUNC_DIR/__ftmux_pick_id.fish が存在しません"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fzf stub: 先頭行をそのまま選んだことにする。引数は検証用に記録する
cat >"$tmp/fzf" <<'EOF'
#!/bin/bash
echo "$*" >>"${FZF_ARGS:?}"
head -1
EOF
chmod +x "$tmp/fzf"

export FZF_ARGS="$tmp/fzf-args"
: >"$FZF_ARGS"

# fish を隔離環境で実行する。--no-config を付けないと、ユーザーの config.fish が
# PATH を組み直して stub より実物の fzf が先に来る（実際にそうなった）
run_fish() {
  env PATH="$tmp:$PATH" FZF_ARGS="$FZF_ARGS" fish --no-config -c "
    set -g fish_function_path '$FUNC_DIR' \$fish_function_path
    $1
  " 2>&1
}

TAB=$'\t'

# ID列（1列目）だけを返す
out=$(run_fish "printf 'id1\tひとつめ\nid2\tふたつめ\n' | __ftmux_pick_id 'prompt> ' '$TAB'")
check "選択行のID列を返す" test "$out" = "id1"

# 表示は2列目、区切りは渡した文字
check "fzfへdelimiterを渡す" grep -q -- "--delimiter" "$FZF_ARGS"
check "fzfへwith-nth=2を渡す" grep -q -- "--with-nth=2" "$FZF_ARGS"
check "promptがfzfへ渡る" grep -q -- "prompt>" "$FZF_ARGS"

# 選択なし（空）なら非0
cat >"$tmp/fzf" <<'EOF'
#!/bin/bash
cat >/dev/null
EOF
chmod +x "$tmp/fzf"
run_fish "printf 'id1\tx\n' | __ftmux_pick_id 'p> ' '$TAB'; echo rc=\$status" >"$tmp/empty-out"
check "選択が空なら非0を返す" grep -q "rc=1" "$tmp/empty-out"

# 呼び出し元のローカル変数を汚さない（--no-scope-shadowing を外したことの確認）
out=$(run_fish "
  function caller
    set -l line 'もとの値'
    printf 'id1\tx\n' | __ftmux_pick_id 'p> ' '$TAB' >/dev/null
    echo \$line
  end
  caller")
check "呼び出し元のローカル変数を壊さない" test "$out" = "もとの値"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
