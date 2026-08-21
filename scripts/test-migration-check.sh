#!/bin/bash
# migration-check.sh のテスト。使い捨ての git リポジトリを組み立てて、
# ローカル専用の作業状態（remote無し・未push・stash・dirty・worktree）の
# 検出と終了コードを確認する
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/migration-check.sh"

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

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# テスト用リポジトリの共通初期化。ユーザー設定はリポジトリローカルに閉じる
new_repo() {
  local d="$1"
  git init -q -b main "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
}

commit_file() {
  local d="$1" f="$2"
  echo x >"$d/$f"
  git -C "$d" add "$f"
  git -C "$d" commit -qm "add $f"
}

# 共有の bare remote。push 済みリポジトリの「きれいな状態」を作るのに使う
make_pushed_repo() {
  local d="$1"
  new_repo "$d"
  commit_file "$d" base.txt
  git init -q --bare "$d.remote"
  git -C "$d" remote add origin "$d.remote"
  git -C "$d" push -qu origin main
}

# 1) すべて push 済みのきれいなリポジトリ → 報告されない
make_pushed_repo "$tmp/clean"

# 2) 未push コミットが1つ
make_pushed_repo "$tmp/unpushed"
commit_file "$tmp/unpushed" extra.txt

# 3) remote が無い
new_repo "$tmp/noremote"
commit_file "$tmp/noremote" a.txt

# 4) stash が1つ
make_pushed_repo "$tmp/stashed"
echo y >"$tmp/stashed/base.txt"
git -C "$tmp/stashed" stash -q

# 5) 未追跡ファイルで dirty
make_pushed_repo "$tmp/dirty"
echo z >"$tmp/dirty/untracked.txt"

# 6) worktree が1つ
make_pushed_repo "$tmp/withwt"
git -C "$tmp/withwt" worktree add -q "$tmp/withwt-wt" -b wt-branch

# 7) git リポジトリではないディレクトリ → 黙って飛ばす
mkdir -p "$tmp/notrepo"

out=$(bash "$TARGET" \
  "$tmp/clean" "$tmp/unpushed" "$tmp/noremote" "$tmp/stashed" \
  "$tmp/dirty" "$tmp/withwt" "$tmp/notrepo" 2>&1)
rc=$?

check "作業状態があると終了コード1" test "$rc" -eq 1
check "きれいなリポジトリは報告しない" bash -c "! grep -q '/clean ' <<<'$out'"
check "未pushコミットを検出する" bash -c "grep '/unpushed' <<<'$out' | grep -q 'unpushed:1'"
check "remote無しを検出する" bash -c "grep '/noremote' <<<'$out' | grep -q 'remote:なし'"
check "stashを検出する" bash -c "grep '/stashed' <<<'$out' | grep -q 'stash:1'"
check "dirtyを検出する" bash -c "grep '/dirty' <<<'$out' | grep -q 'dirty:1'"
check "worktreeを検出する" bash -c "grep '/withwt ' <<<'$out' | grep -q 'worktree:1'"
check "非gitディレクトリは報告しない" bash -c "! grep -q '/notrepo' <<<'$out'"

# きれいなリポジトリだけなら終了コード0
out2=$(bash "$TARGET" "$tmp/clean" 2>&1)
check "全リポジトリきれいなら終了コード0" test "$?" -eq 0
check "きれいなときは件数サマリを出す" grep -q "0/1" <<<"$out2"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
