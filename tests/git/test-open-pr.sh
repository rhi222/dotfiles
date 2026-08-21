#!/bin/bash
# fish関数 open-pr の characterization test
#
# 現在ブランチの PR をブラウザで開く。gh が branch -> PR を引けない場合
# （worktree / fork）に備えて解決経路が4段あり、どれも `gh browse <url>` に
# 収束する。その順序と打ち切り条件を固定する。
#
#   1. gh pr view --json url                       （fast path）
#   2. gh pr list --head <branch>
#   3. gh pr list --search "head:<branch>"
#   4. gh pr list --search "head:<owner>:<branch>" （owner は gh repo view から）
#
# gh / git は PATH 前方の stub に差し替える。stub は引数列で分岐し、呼ばれた
# コマンドを GH_LOG に記録する。どの段で当たったかは「browse したか」と
# 「そこまでに何を呼んだか」で判定する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"
OPEN_PR="$FUNC_DIR/open-pr.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
if [[ ! -f "$OPEN_PR" ]]; then
  echo "ERROR: $OPEN_PR が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
GH_LOG=""

setup() {
  TEST_DIR=$(mktemp -d)
  TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
  STUB_DIR="$TEST_DIR/bin"
  GH_LOG="$TEST_DIR/gh.log"
  mkdir -p "$STUB_DIR"
  : >"$GH_LOG"

  # gh stub。経路ごとに「URL を返すか空を返すか」を環境変数で切り替える。
  #   GH_VIEW_URL    `gh pr view --json url` の戻り（空なら未設定扱い）
  #   GH_HEAD_URL    `gh pr list --head ...` の戻り
  #   GH_SEARCH_URL  `gh pr list --search head:<branch>` の戻り
  #   GH_OWNER_URL   `gh pr list --search head:<owner>:<branch>` の戻り
  #   GH_OWNER       `gh repo view` が返す owner
  #   GH_BROWSE_RC   `gh browse` の終了コード
  # 空文字は「PR が見つからない」。gh --jq は見つからないとき null を出すので
  # それも再現する（NULL_ON_MISS=1）。
  cat >"$STUB_DIR/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"

emit() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
  elif [ "${NULL_ON_MISS:-0}" = "1" ]; then
    printf 'null\n'
  fi
}

case "$1" in
  browse) exit "${GH_BROWSE_RC:-0}" ;;
  repo) emit "${GH_OWNER:-}" ;;
  pr)
    case "$2" in
      view)
        case "$*" in
          *--web*) exit "${GH_VIEW_WEB_RC:-0}" ;;
          *) emit "${GH_VIEW_URL:-}" ;;
        esac
        ;;
      list)
        case "$*" in
          *--web*) exit 0 ;;
          *--head*) emit "${GH_HEAD_URL:-}" ;;
          *"head:${GH_OWNER:-nobody}:"*) emit "${GH_OWNER_URL:-}" ;;
          *--search*) emit "${GH_SEARCH_URL:-}" ;;
        esac
        ;;
    esac
    ;;
esac
exit 0
STUB
  chmod +x "$STUB_DIR/gh"

  # git stub。`git branch --show-current` だけ返す
  cat >"$STUB_DIR/git" <<'STUB'
#!/bin/bash
if [ "$1" = "branch" ]; then
  [ -n "${GIT_BRANCH:-}" ] && printf '%s\n' "$GIT_BRANCH"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_DIR/git"
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# open-pr を隔離実行する。末尾に rc=<status> を出す。
run_open_pr() {
  env PATH="$STUB_DIR:/usr/bin:/bin" \
    GH_LOG="$GH_LOG" \
    "$@" \
    fish --no-config -c "
      source '$OPEN_PR'
      open-pr \$OPEN_PR_ARGS
      echo rc=\$status
    " 2>&1
}

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

rc_of() { printf '%s' "$1" | sed -n 's/^rc=//p' | tail -1; }
browsed() { grep -q '^browse ' "$GH_LOG" && echo yes || echo no; }
browsed_url() { sed -n 's/^browse //p' "$GH_LOG" | tail -1; }
called() { grep -qF -- "$1" "$GH_LOG" && echo yes || echo no; }

echo "== gh が無いとき =="

setup
out=$(env PATH="/nonexistent" GH_LOG="$GH_LOG" /usr/bin/fish --no-config -c \
  "source '$OPEN_PR'; open-pr; echo rc=\$status" 2>&1)
check "gh が無ければ 1 で終わる" "1" "$(rc_of "$out")"
check "理由を出す" "yes" "$(grep -q 'gh command not found' <<<"$out" && echo yes || echo no)"
teardown

echo "== 引数があるとき =="

setup
out=$(run_open_pr OPEN_PR_ARGS=123)
check "引数はそのまま gh pr view --web に渡す" "yes" "$(called 'pr view --web 123')"
check "URL 解決の経路には入らない" "no" "$(browsed)"
check "gh の終了コードを返す" "0" "$(rc_of "$out")"
teardown

setup
out=$(run_open_pr OPEN_PR_ARGS=123 GH_VIEW_WEB_RC=1)
check "引数経路でも gh の失敗を隠さない" "1" "$(rc_of "$out")"
teardown

echo "== 経路1: gh pr view で引けるとき =="

setup
out=$(run_open_pr GH_VIEW_URL=https://example.com/pr/1)
check "browse する" "yes" "$(browsed)"
check "経路1の URL を開く" "https://example.com/pr/1" "$(browsed_url)"
check "以降の経路は呼ばない" "no" "$(called 'pr list')"
# 副作用（ブラウザ起動）を URL 取得から分離しているので、branch も引かない
check "branch も引かない" "0" "$(grep -c 'pr list' "$GH_LOG")"
check "成功で終わる" "0" "$(rc_of "$out")"
teardown

setup
out=$(run_open_pr GH_VIEW_URL=https://example.com/pr/1 GH_BROWSE_RC=1)
check "browse の失敗はそのまま返す" "1" "$(rc_of "$out")"
teardown

echo "== 経路2: --head で引けるとき（worktree 相当） =="

setup
out=$(run_open_pr GIT_BRANCH=feat/x GH_HEAD_URL=https://example.com/pr/2)
check "経路1を試したうえで" "yes" "$(called 'pr view --json url')"
check "経路2の URL を開く" "https://example.com/pr/2" "$(browsed_url)"
check "--head にブランチ名を渡す" "yes" "$(called '--head feat/x')"
check "成功で終わる" "0" "$(rc_of "$out")"
teardown

echo "== 経路3: search head:<branch> =="

setup
out=$(run_open_pr GIT_BRANCH=feat/x GH_SEARCH_URL=https://example.com/pr/3)
check "経路3の URL を開く" "https://example.com/pr/3" "$(browsed_url)"
check "head:<branch> で検索する" "yes" "$(called 'head:feat/x')"
teardown

echo "== 経路4: search head:<owner>:<branch>（fork 相当） =="

setup
out=$(run_open_pr GIT_BRANCH=feat/x GH_OWNER=someowner GH_OWNER_URL=https://example.com/pr/4)
check "owner を gh repo view から引く" "yes" "$(called 'repo view')"
check "経路4の URL を開く" "https://example.com/pr/4" "$(browsed_url)"
check "head:<owner>:<branch> で検索する" "yes" "$(called 'head:someowner:feat/x')"
check "成功で終わる" "0" "$(rc_of "$out")"
teardown

echo "== ブランチが取れないとき =="

setup
out=$(run_open_pr)
# 経路2以降はすべてブランチ名を必要とするので、ここで打ち切る
check "1 で終わる" "1" "$(rc_of "$out")"
check "理由を出す" "yes" \
  "$(grep -q 'could not detect current branch' <<<"$out" && echo yes || echo no)"
check "browse しない" "no" "$(browsed)"
teardown

echo "== どこにも見つからないとき =="

setup
out=$(run_open_pr GIT_BRANCH=feat/x GH_OWNER=someowner)
check "1 で終わる" "1" "$(rc_of "$out")"
check "ブランチ名を添えて報告する" "yes" \
  "$(grep -q "no open pull request found for branch 'feat/x'" <<<"$out" && echo yes || echo no)"
check "最後の手段として一覧をブラウザで開く" "yes" "$(called 'pr list --web')"
check "browse はしない" "no" "$(browsed)"
teardown

echo "== gh --jq の null を「見つからない」として扱う =="

setup
# gh は --jq で該当が無いとき空ではなく null を出す。文字列 "null" を URL として
# browse に渡すと壊れるので、各経路で弾いている
out=$(run_open_pr GIT_BRANCH=feat/x NULL_ON_MISS=1 GH_OWNER=someowner)
check "null では browse しない" "no" "$(browsed)"
check "1 で終わる" "1" "$(rc_of "$out")"
teardown

setup
out=$(run_open_pr GIT_BRANCH=feat/x NULL_ON_MISS=1 GH_SEARCH_URL=https://example.com/pr/3)
check "null を挟んでも後段の経路へ進む" "https://example.com/pr/3" "$(browsed_url)"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
