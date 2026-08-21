#!/bin/bash
# gf の ghq list キャッシュまわりのユニットテスト
#
# 対象は3つ。
#   __ghq_list_cache_path     キャッシュのパス解決（テストで差し替えられること）
#   __ghq_list_cache_refresh  キャッシュのアトミック更新
#   ghq（fish関数のラッパー）  リポジトリ集合が変わるサブコマンドの後に更新すること
#   gf                        fzf 起動「前」に更新を投げること（ESCでも更新される）
#
# ghq / fzf は stub をPATHに置いて実物を呼ばない。fish は --no-config で起動し、
# 関数だけを fish_function_path 経由で autoload させる。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
for f in __ghq_list_cache_path.fish __ghq_list_cache_refresh.fish ghq.fish gf.fish; do
  if [[ ! -f "$FUNC_DIR/$f" ]]; then
    echo "ERROR: $FUNC_DIR/$f が存在しません"
    exit 1
  fi
done

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
TEST_HOME=""
CACHE=""
GHQ_STUB_LIST=""
GHQ_STUB_ROOT=""

setup() {
  TEST_DIR=$(mktemp -d)
  TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
  STUB_DIR="$TEST_DIR/bin"
  TEST_HOME="$TEST_DIR/home"
  CACHE="$TEST_DIR/cache/ghq-list"
  GHQ_STUB_LIST="$TEST_DIR/ghq-repos.txt"
  GHQ_STUB_ROOT="$TEST_DIR/ghq-root"
  mkdir -p "$STUB_DIR" "$TEST_HOME" "$TEST_DIR/cache" "$GHQ_STUB_ROOT"

  printf '%s\n' github.com/rhi222/dotfiles github.com/rhi222/old >"$GHQ_STUB_LIST"

  # ghq stub。挙動は環境変数で切り替える。
  #   GHQ_STUB_LIST_FAIL  list を失敗させる（stderr に出力）
  #   GHQ_STUB_GET_FAIL   get を失敗させる
  cat >"$STUB_DIR/ghq" <<'STUB'
#!/bin/bash
case "$1" in
  root)
    echo "$GHQ_STUB_ROOT"
    ;;
  list)
    if [[ -n "${GHQ_STUB_LIST_FAIL:-}" ]]; then
      echo "ghq: stub list failure" >&2
      exit 1
    fi
    cat "$GHQ_STUB_LIST"
    ;;
  get | clone | rm | create | migrate)
    echo "stub-stdout: $1 ${2:-}"
    echo "stub-stderr: $1 ${2:-}" >&2
    if [[ -n "${GHQ_STUB_GET_FAIL:-}" ]]; then
      exit 3
    fi
    # リポジトリが増えた（あるいは減った）状態を list に反映する
    if [[ "$1" == rm ]]; then
      grep -vF -- "${2:-}" "$GHQ_STUB_LIST" >"$GHQ_STUB_LIST.new" || true
      mv "$GHQ_STUB_LIST.new" "$GHQ_STUB_LIST"
    else
      echo "${2:-}" >>"$GHQ_STUB_LIST"
    fi
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "$STUB_DIR/ghq"

  # fzf stub。FZF_STUB_OUT を返し FZF_STUB_RC で終了する。
  cat >"$STUB_DIR/fzf" <<'STUB'
#!/bin/bash
cat >/dev/null
if [[ -n "${FZF_STUB_OUT:-}" ]]; then
  echo "$FZF_STUB_OUT"
fi
exit "${FZF_STUB_RC:-0}"
STUB
  chmod +x "$STUB_DIR/fzf"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# fish を隔離環境で実行する。$1 に fish のコードを渡す。
run_fish() {
  env HOME="$TEST_HOME" \
    PATH="$STUB_DIR:$PATH" \
    GHQ_STUB_ROOT="$GHQ_STUB_ROOT" \
    GHQ_STUB_LIST="$GHQ_STUB_LIST" \
    GHQ_STUB_LIST_FAIL="${GHQ_STUB_LIST_FAIL:-}" \
    GHQ_STUB_GET_FAIL="${GHQ_STUB_GET_FAIL:-}" \
    FZF_STUB_OUT="${FZF_STUB_OUT:-}" \
    FZF_STUB_RC="${FZF_STUB_RC:-0}" \
    fish --no-config -c "
      set -g fish_function_path '$FUNC_DIR' \$fish_function_path
      set -g ghq_list_cache '$CACHE'
      $1
    " 2>&1
}

assert_eq() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual:              $haystack"
  fi
}

# background 更新を待つ。最大 5 秒。
wait_for_cache_line() {
  local needle="$1"
  for _ in $(seq 1 50); do
    if [[ -f "$CACHE" ]] && grep -qF -- "$needle" "$CACHE"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

echo "=== gf キャッシュ テスト ==="
echo ""

# --- 1. __ghq_list_cache_path ---
echo "[1] __ghq_list_cache_path"
setup
assert_eq "$TEST_HOME/.cache/ghq-list" \
  "$(env HOME="$TEST_HOME" PATH="$STUB_DIR:$PATH" fish --no-config -c \
    "set -g fish_function_path '$FUNC_DIR' \$fish_function_path; __ghq_list_cache_path" 2>&1)" \
  "既定は \$HOME/.cache/ghq-list"
assert_eq "$CACHE" "$(run_fish '__ghq_list_cache_path')" \
  "\$ghq_list_cache で上書きできる"
teardown
echo ""

# --- 2. __ghq_list_cache_refresh: 成功時 ---
echo "[2] __ghq_list_cache_refresh（成功）"
setup
out=$(run_fish '__ghq_list_cache_refresh; echo rc=$status')
assert_eq "rc=0" "$(echo "$out" | tail -1)" "成功時は 0 を返す"
assert_eq "github.com/rhi222/dotfiles
github.com/rhi222/old" "$(cat "$CACHE")" "ghq list の結果を書き込む"
assert_eq "0" "$(find "$TEST_DIR/cache" -name 'ghq-list*.tmp' | wc -l)" ".tmp を残さない"
teardown
echo ""

# --- 3. __ghq_list_cache_refresh: 失敗時はキャッシュを壊さない ---
echo "[3] __ghq_list_cache_refresh（失敗）"
setup
printf '%s\n' github.com/rhi222/keepme >"$CACHE"
GHQ_STUB_LIST_FAIL=1
out=$(run_fish '__ghq_list_cache_refresh; echo rc=$status')
unset GHQ_STUB_LIST_FAIL
assert_eq "rc=1" "$(echo "$out" | tail -1)" "失敗時は 1 を返す"
assert_eq "github.com/rhi222/keepme" "$(cat "$CACHE")" "既存のキャッシュを壊さない"
assert_eq "0" "$(find "$TEST_DIR/cache" -name 'ghq-list*.tmp' | wc -l)" "失敗時も .tmp を残さない"
assert_contains "$(cat "$CACHE.err" 2>&1)" "stub list failure" "stderr を .err に残す"
teardown
echo ""

# --- 4. ghq ラッパー: get の後にキャッシュを更新する（本題） ---
echo "[4] ghq ラッパー（get 成功）"
setup
run_fish '__ghq_list_cache_refresh' >/dev/null
out=$(run_fish 'ghq get github.com/rhi222/brandnew; echo rc=$status')
assert_eq "rc=0" "$(echo "$out" | tail -1)" "ghq の終了ステータスを透過する"
assert_contains "$out" "stub-stdout: get github.com/rhi222/brandnew" "stdout を素通しする"
assert_contains "$out" "stub-stderr: get github.com/rhi222/brandnew" "stderr を素通しする"
assert_contains "$(cat "$CACHE")" "github.com/rhi222/brandnew" \
  "clone 直後にキャッシュへ反映される（同期更新）"
teardown
echo ""

# --- 5. ghq ラッパー: 失敗時は更新しない ---
echo "[5] ghq ラッパー（get 失敗）"
setup
run_fish '__ghq_list_cache_refresh' >/dev/null
GHQ_STUB_GET_FAIL=1
out=$(run_fish 'ghq get github.com/rhi222/nope; echo rc=$status')
unset GHQ_STUB_GET_FAIL
assert_eq "rc=3" "$(echo "$out" | tail -1)" "失敗時も終了ステータスを透過する"
assert_eq "github.com/rhi222/dotfiles
github.com/rhi222/old" "$(cat "$CACHE")" "失敗時はキャッシュを更新しない"
teardown
echo ""

# --- 6. ghq ラッパー: 集合が変わるサブコマンドすべてで更新する ---
echo "[6] ghq ラッパー（対象サブコマンド）"
for sub in get clone create migrate; do
  setup
  run_fish '__ghq_list_cache_refresh' >/dev/null
  run_fish "ghq $sub github.com/rhi222/added-by-$sub" >/dev/null
  assert_contains "$(cat "$CACHE")" "github.com/rhi222/added-by-$sub" \
    "ghq $sub でキャッシュを更新する"
  teardown
done

# rm は減る側
setup
run_fish '__ghq_list_cache_refresh' >/dev/null
run_fish 'ghq rm github.com/rhi222/old' >/dev/null
assert_eq "github.com/rhi222/dotfiles" "$(cat "$CACHE")" "ghq rm でキャッシュを更新する"
teardown
echo ""

# --- 7. ghq ラッパー: 読み取り系サブコマンドでは更新しない ---
echo "[7] ghq ラッパー（読み取り系）"
setup
printf '%s\n' stale-entry >"$CACHE"
run_fish 'ghq list' >/dev/null
assert_eq "stale-entry" "$(cat "$CACHE")" "ghq list ではキャッシュを更新しない"
run_fish 'ghq root' >/dev/null
assert_eq "stale-entry" "$(cat "$CACHE")" "ghq root ではキャッシュを更新しない"
out=$(run_fish 'ghq; echo rc=$status')
assert_eq "rc=0" "$(echo "$out" | tail -1)" "引数なしでもエラーにしない"
teardown
echo ""

# --- 8. gf: fzf をキャンセルしてもキャッシュが更新される（今回のバグの回帰） ---
echo "[8] gf（fzf キャンセル時も更新）"
setup
printf '%s\n' stale-entry >"$CACHE"
FZF_STUB_RC=130
out=$(run_fish 'gf; echo rc=$status')
unset FZF_STUB_RC
# `or return` は引数なしなので fzf の終了ステータス（ESC は 130）がそのまま返る
assert_eq "rc=130" "$(echo "$out" | tail -1)" "キャンセル時は fzf の終了ステータスを返す"
if wait_for_cache_line github.com/rhi222/dotfiles; then
  assert_eq "github.com/rhi222/dotfiles
github.com/rhi222/old" "$(cat "$CACHE")" "ESC で抜けてもキャッシュが更新される"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: ESC で抜けてもキャッシュが更新される（5秒待っても更新されない）"
fi
teardown
echo ""

# --- 9. gf: 選択して cd できる ---
echo "[9] gf（選択）"
setup
mkdir -p "$GHQ_STUB_ROOT/github.com/rhi222/dotfiles"
FZF_STUB_OUT=github.com/rhi222/dotfiles
out=$(run_fish 'gf; echo "pwd=$PWD"')
unset FZF_STUB_OUT
assert_eq "pwd=$GHQ_STUB_ROOT/github.com/rhi222/dotfiles" "$(echo "$out" | tail -1)" \
  "選択したリポジトリへ cd する"
teardown
echo ""

# --- 10. gf: キャッシュが無い初回は同期的に作ってから表示する ---
echo "[10] gf（初回）"
setup
rm -f "$CACHE"
FZF_STUB_RC=130
run_fish 'gf' >/dev/null
unset FZF_STUB_RC
assert_eq "github.com/rhi222/dotfiles
github.com/rhi222/old" "$(cat "$CACHE" 2>&1)" "キャッシュを同期的に作る"
teardown
echo ""

# =============================================================================
echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
echo ""
if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
else
  echo "全テスト成功"
  exit 0
fi
