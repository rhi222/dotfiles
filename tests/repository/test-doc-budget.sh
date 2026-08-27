#!/bin/bash
# doc-budget.sh のユニットテスト
#
# AGENTS.md は毎セッションのコンテキストに丸ごと載るので、行数に予算を付けて
# 超過を機械的に落とす。**散文の規約（「表と数個の理由だけ」）が守られず、
# 圧縮を2回やって2回とも数日で戻ったため機械化した**（pr-base-guard と同じ理由）。
#
# 予算は「ファイル全体」と「1セクション」の二段。全体だけだと肥大した1節を
# 見逃し、セクションだけだと 43節×20行 でファイルは縮まない（実測）。
#
# REPO を差し替えて実行する。ネットワークにも実環境にも触らない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
TARGET="$SCRIPTS_DIR/repository/doc-budget.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/scripts/repository"
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# 宣言リストを書く。書式は `<path> <ファイル全体の上限> <1セクションの上限>`
declare_budget() {
  printf '%s\n' "$@" >"$REPO/scripts/repository/doc-budget.txt"
}

# 指定行数の本文を持つセクションを作る（見出し1行 + 本文 n-1 行）
make_section() {
  local heading="$1" lines="$2" i
  echo "$heading"
  for ((i = 1; i < lines; i++)); do echo "body $i"; done
}

run_budget() {
  env DOC_BUDGET_REPO="$REPO" bash "$TARGET" "$@" 2>&1
}

# --staged の検査には本物の git リポジトリが要る
init_git() {
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
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

has() { grep -q -- "$1" <<<"$2" && echo yes || echo no; }

echo "== 予算内 =="

setup
declare_budget 'DOC.md 20 10'
{
  echo '# DOC'
  make_section '## alpha' 5
  make_section '### beta' 5
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "予算内なら成功で返す" "0" "$rc"
check "OK を伝える" "yes" "$(has 'doc-budget: OK' "$out")"
teardown

echo "== ファイル全体の超過 =="

setup
declare_budget 'DOC.md 10 100'
{
  echo '# DOC'
  make_section '## alpha' 20
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "全体超過なら失敗で返す" "1" "$rc"
check "全体超過だと分かる" "yes" "$(has 'ファイル全体' "$out")"
check "上限値を出す" "yes" "$(has '10' "$out")"
teardown

echo "== 1セクションの超過 =="

setup
# 全体は予算内。セクションだけが超過している状態を作る
declare_budget 'DOC.md 100 10'
{
  echo '# DOC'
  make_section '### fat-one' 20
  make_section '### thin-one' 5
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "セクション超過なら失敗で返す" "1" "$rc"
check "超過したセクション名を出す" "yes" "$(has 'fat-one' "$out")"
check "予算内のセクションは出さない" "no" "$(has 'thin-one' "$out")"
teardown

echo "== 余裕の表示（ratchet の要） =="

setup
# 上限を手で下げ忘れないよう、予算内でも残りを出す
declare_budget 'DOC.md 20 10'
{
  echo '# DOC'
  make_section '## alpha' 5
} >"$REPO/DOC.md"
out=$(run_budget)
check "全体の余裕を出す" "yes" "$(has '余裕' "$out")"
teardown

echo "== 見出しの数え方 =="

setup
# コードブロックの中の `## ` はシェルのコメントであって見出しではない。
# crontab の例に `# 0 9,11,13,15,17,19 * * 1-5 ...` があるように、
# md の本文にはコメント行がそのまま入る
declare_budget 'DOC.md 100 10'
{
  echo '# DOC'
  echo '## real'
  echo '```fish'
  echo '## これは見出しではない'
  echo '### これも見出しではない'
  echo '```'
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "body $i"; done
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "コードブロック内は見出しにしない（超過を検出する）" "1" "$rc"
check "コードブロック内の行をセクション名にしない" "no" \
  "$(has 'これは見出しではない' "$out")"
teardown

setup
# #### は親セクションに含める（AGENTS.md の「復元の進み具合を見る」がこれ）
declare_budget 'DOC.md 100 10'
{
  echo '# DOC'
  make_section '### parent' 6
  make_section '#### child' 6
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "#### を親に含める（合算で超過する）" "1" "$rc"
check "#### 自体をセクションとして数えない" "no" "$(has 'child' "$out")"
teardown

setup
# 最初の見出しより前（h1 とリード文）はセクション予算の対象外。
# 全体の行数にだけ数える
declare_budget 'DOC.md 100 5'
{
  echo '# DOC'
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "lead $i"; done
  make_section '## alpha' 3
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "リード文はセクション予算の対象外" "0" "$rc"
teardown

echo "== --staged =="

setup
init_git
declare_budget 'DOC.md 10 100'
{
  echo '# DOC'
  make_section '## alpha' 5
} >"$REPO/DOC.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
# 作業ツリーだけを予算超過にする。commit されるのは index の内容なので、
# --staged はこれを数えてはいけない
{
  echo '# DOC'
  make_section '## alpha' 50
} >"$REPO/DOC.md"
out=$(run_budget --staged)
rc=$?
check "--staged は未ステージの編集を数えない" "0" "$rc"
out=$(run_budget)
rc=$?
check "既定は作業ツリーを数える" "1" "$rc"
teardown

setup
init_git
declare_budget 'DOC.md 10 100'
{
  echo '# DOC'
  make_section '## alpha' 5
} >"$REPO/DOC.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init
{
  echo '# DOC'
  make_section '## alpha' 50
} >"$REPO/DOC.md"
git -C "$REPO" add DOC.md
out=$(run_budget --staged)
rc=$?
check "--staged はステージ済みの超過を検出する" "1" "$rc"
teardown

echo "== 宣言リストの読み方 =="

setup
declare_budget '# コメント行' '' 'DOC.md 20 10' '   ' '# 末尾のコメント'
{
  echo '# DOC'
  make_section '## alpha' 5
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "コメント行と空行を無視する" "0" "$rc"
check "宣言した1件を検査する" "yes" "$(has 'DOC.md' "$out")"
teardown

setup
declare_budget 'A.md 20 10' 'B.md 20 10'
{
  echo '# A'
  make_section '## alpha' 5
} >"$REPO/A.md"
{
  echo '# B'
  make_section '## beta' 50
} >"$REPO/B.md"
out=$(run_budget)
rc=$?
check "複数ファイルを宣言できる" "1" "$rc"
check "予算内のファイルも報告する" "yes" "$(has 'A.md' "$out")"
check "超過したファイルを報告する" "yes" "$(has 'B.md' "$out")"
teardown

setup
# 数値でない上限は宣言の書き間違い。黙って通すと検査が消える
declare_budget 'DOC.md twenty 10'
{
  echo '# DOC'
  make_section '## alpha' 5
} >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "不正な上限値は失敗で返す" "1" "$rc"
check "どの行が不正か伝える" "yes" "$(has 'doc-budget.txt' "$out")"
teardown

setup
# 列が足りない行も同じ扱い
declare_budget 'DOC.md 20'
: >"$REPO/DOC.md"
out=$(run_budget)
rc=$?
check "列が足りない行は失敗で返す" "1" "$rc"
teardown

echo "== 読めないとき =="

setup
# 宣言リストが無い環境では警告して通す。dotfilesLink.sh を走らせる前の
# 新環境で commit できなくなるのを避ける（secret-scan の辞書と同じ判断）
out=$(run_budget)
rc=$?
check "宣言リストが無ければ成功で返す" "0" "$rc"
check "無いことを伝える" "yes" "$(has 'doc-budget.txt' "$out")"
teardown

setup
# 宣言にあるファイルが無い場合も通す。pre-commit を壊すほうが害が大きい
declare_budget 'MISSING.md 20 10'
out=$(run_budget)
rc=$?
check "対象ファイルが無ければ成功で返す" "0" "$rc"
check "skip したことを伝える" "yes" "$(has 'MISSING.md' "$out")"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
