#!/bin/bash
# .config/claude/hooks/pr-base-guard.sh のユニットテスト
#
# PreToolUse(Bash) hook として stdin に Claude Code の hook JSON を受け取り、
# `gh pr create --base <非デフォルトブランチ>` を検出したら permissionDecision:ask を返す。
#
# 「素通し」の契約は「stdout が空 かつ exit 0」。PreToolUse は stdout に何も
# 出さなければ既定の権限判定に落ちるため、空であることまで見ないと意味がない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../.config/claude/hooks/pr-base-guard.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "ERROR: $TARGET が実行可能ファイルとして存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# 既定ブランチ main を origin/HEAD で宣言したリポジトリ
REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# origin/HEAD を持たないリポジトリ（init.defaultBranch へのフォールバック検証用）
REPO_NO_ORIGIN="$TMPROOT/repo-no-origin"
mkdir -p "$REPO_NO_ORIGIN"
git -C "$REPO_NO_ORIGIN" init -q -b trunk
git -C "$REPO_NO_ORIGIN" config init.defaultBranch trunk

# git リポジトリではないディレクトリ
NOT_REPO="$TMPROOT/not-repo"
mkdir -p "$NOT_REPO"

# stdin はパイプではなくファイルで渡す。パイプだと hook が stdin を読み切る前に
# 終了したとき書き手が SIGPIPE で死に、終了コードが 141 に化けて判定が濁る。
payload_file() {
  local cwd="$1" cmd="$2" out="$TMPROOT/payload.json"
  jq -n --arg cwd "$cwd" --arg cmd "$cmd" \
    '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$cwd, tool_input:{command:$cmd}}' >"$out"
  printf '%s' "$out"
}

run_target() {
  local cwd="$1" cmd="$2"
  "$TARGET" <"$(payload_file "$cwd" "$cmd")"
}

# 素通し = stdout が空 かつ exit 0
assert_passthrough() {
  local name="$1" cwd="$2" cmd="$3"
  local out rc
  out=$(run_target "$cwd" "$cmd")
  rc=$?
  TOTAL=$((TOTAL + 1))
  if [[ $rc -eq 0 && -z "$out" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "        素通し（stdout 空 / exit 0）を期待"
    echo "        実際: exit $rc / stdout [$out]"
  fi
}

# ask = permissionDecision が ask で、理由に gh-stack への誘導が入る
assert_ask() {
  local name="$1" cwd="$2" cmd="$3"
  local out rc decision reason
  out=$(run_target "$cwd" "$cmd")
  rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  TOTAL=$((TOTAL + 1))
  if [[ $rc -eq 0 && "$decision" == "ask" && "$reason" == *"gh-stack"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "        exit 0 / permissionDecision=ask / 理由に gh-stack を期待"
    echo "        実際: exit $rc / decision [$decision] / stdout [$out]"
  fi
}

echo "== 非デフォルト base は ask で割り込む =="
assert_ask "--base に feature ブランチ" "$REPO" "gh pr create --base feat/base-layer --title x --body y"
assert_ask "--base= のイコール形" "$REPO" "gh pr create --base=feat/base-layer --title x"
assert_ask "-B の短縮形" "$REPO" "gh pr create -B feat/base-layer --title x"
assert_ask "前後に別コマンドが連なる" "$REPO" "cd /tmp && gh pr create --base feat/x --fill"
assert_ask "gh と pr create の間隔が広い" "$REPO" "gh   pr   create   --base   feat/x"
assert_ask "origin/HEAD が無ければ init.defaultBranch と比べる" "$REPO_NO_ORIGIN" "gh pr create --base feat/x"

echo "== 既定ブランチ向けは素通し =="
assert_passthrough "--base main" "$REPO" "gh pr create --base main --title x"
assert_passthrough "--base=main" "$REPO" "gh pr create --base=main --title x"
assert_passthrough "origin/ 付きの指定" "$REPO" "gh pr create --base origin/main --title x"
assert_passthrough "init.defaultBranch と一致" "$REPO_NO_ORIGIN" "gh pr create --base trunk --title x"

echo "== 判定対象外は素通し =="
assert_passthrough "--base 指定なし（gh が既定ブランチを使う）" "$REPO" "gh pr create --fill"
assert_passthrough "gh pr view" "$REPO" "gh pr view 123 --json baseRefName"
assert_passthrough "gh pr list に --base がある" "$REPO" "gh pr list --base feat/x"
assert_passthrough "gh stack は gh-stack 自身なので通す" "$REPO" "gh stack create --base feat/x"
assert_passthrough "gh 以外のコマンドの --base" "$REPO" "git rebase --onto main --base feat/x"
assert_passthrough "空のコマンド" "$REPO" ""

echo "== 壊さない（フェイルオープン） =="
assert_passthrough "git リポジトリでない cwd" "$NOT_REPO" "gh pr create --base feat/x"
assert_passthrough "cwd が存在しない" "$TMPROOT/missing" "gh pr create --base feat/x"

# jq 不在: 必要なコマンドだけを並べた PATH で走らせる。
# shebang を解決する env / bash 自体も並べないと jq 以外の理由で落ちる。
STUBBIN="$TMPROOT/stubbin"
mkdir -p "$STUBBIN"
for c in env bash cat git grep sed head tr cut basename dirname; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$STUBBIN/$c"
done
TOTAL=$((TOTAL + 1))
jq_out=$(env PATH="$STUBBIN" "$TARGET" <"$(payload_file "$REPO" "gh pr create --base feat/x")")
jq_rc=$?
if [[ $jq_rc -eq 0 && -z "$jq_out" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: jq が無い環境では素通しする"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: jq が無い環境では素通しする"
  echo "        実際: exit $jq_rc / stdout [$jq_out]"
fi

# 壊れた JSON を渡しても落ちない
TOTAL=$((TOTAL + 1))
bad_out=$(printf 'not json' | "$TARGET")
bad_rc=$?
if [[ $bad_rc -eq 0 && -z "$bad_out" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: 壊れた JSON でも素通しする"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 壊れた JSON でも素通しする"
  echo "        実際: exit $bad_rc / stdout [$bad_out]"
fi

echo "== 理由文の中身 =="
reason=$(run_target "$REPO" "gh pr create --base feat/base-layer" | jq -r '.hookSpecificOutput.permissionDecisionReason')
for needle in "feat/base-layer" "main" "gh-stack" "backport"; do
  TOTAL=$((TOTAL + 1))
  if [[ "$reason" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: 理由に [$needle] を含む"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: 理由に [$needle] を含む"
    echo "        実際: [$reason]"
  fi
done

echo "---"
echo "pass: $PASS 件 / fail: $FAIL 件 / total: $TOTAL 件"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
