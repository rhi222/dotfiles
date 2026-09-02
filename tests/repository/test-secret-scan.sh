#!/bin/bash
# secret-scan は追跡内容・パス名・外部辞書の機密語を検出し、予約domainなどの
# 公開可能なfixtureを誤検知しない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
SCAN="$SCRIPTS_DIR/repository/secret-scan.sh"

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  [[ -n "${2:-}" ]] && echo "    $2"
  return 0
}

check_exit() {
  local expected="$1" actual="$2" name="$3" out="${4:-}"
  if [[ "$actual" -eq "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "expected exit=$expected, got=$actual / output: $out"
  fi
}

check_contains() {
  local needle="$1" haystack="$2" name="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    ng "$name" "[$needle] を含まない: $haystack"
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/patterns.txt" <<'EOF'
# コメント行は無視される

secretcorp
gitlab\.example-internal
\bZZZ\b
EOF
export SECRET_PATTERNS="$tmp/patterns.txt"

repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t

run_scan() {
  local out exit_code=0
  out=$(cd "$repo" && bash "$SCAN" "$@" 2>&1) || exit_code=$?
  printf '%s\n---EXIT---%s' "$out" "$exit_code"
}
out_of() { printf '%s' "${1%%$'\n'---EXIT---*}"; }
exit_of() { printf '%s' "${1##*---EXIT---}"; }

echo "=== --staged: 機密語を含むファイル ==="
echo "host is secretcorp-internal" >"$repo/a.txt"
git -C "$repo" add a.txt
r=$(run_scan --staged)
check_exit 1 "$(exit_of "$r")" "機密語を検出したら exit 1" "$(out_of "$r")"
check_contains "a.txt" "$(out_of "$r")" "検出したファイル名を出力する"

echo "=== --staged: 機密語を含まないファイル ==="
git -C "$repo" rm -q --cached a.txt
rm "$repo/a.txt"
echo "nothing to see here" >"$repo/b.txt"
git -C "$repo" add b.txt
r=$(run_scan --staged)
check_exit 0 "$(exit_of "$r")" "機密語が無ければ exit 0" "$(out_of "$r")"

echo "=== --staged: パス名に機密語 ==="
mkdir -p "$repo/dir"
echo "clean content" >"$repo/dir/secretcorp-tool.js"
git -C "$repo" add dir/secretcorp-tool.js
r=$(run_scan --staged)
check_exit 1 "$(exit_of "$r")" "パス名の機密語を検出する" "$(out_of "$r")"
check_contains "パス名" "$(out_of "$r")" "パス名の検出だと分かる表示をする"

echo "=== --staged: 単語境界パターン ==="
git -C "$repo" rm -q --cached dir/secretcorp-tool.js
rm -rf "$repo/dir"
echo "PUZZZLE is fine" >"$repo/c.txt"
git -C "$repo" add c.txt
r=$(run_scan --staged)
check_exit 0 "$(exit_of "$r")" "単語の一部にマッチしない" "$(out_of "$r")"
echo "ZZZ alone is not fine" >"$repo/c.txt"
git -C "$repo" add c.txt
r=$(run_scan --staged)
check_exit 1 "$(exit_of "$r")" "独立した単語にマッチする" "$(out_of "$r")"

echo "=== --staged: index の内容を見る（作業ツリーではなく） ==="
# ステージ後に作業ツリーだけ綺麗にしても、index が汚れていれば検出する
git -C "$repo" rm -q --cached c.txt
rm "$repo/c.txt"
echo "secretcorp staged" >"$repo/d.txt"
git -C "$repo" add d.txt
echo "cleaned in worktree" >"$repo/d.txt"
r=$(run_scan --staged)
check_exit 1 "$(exit_of "$r")" "作業ツリーを綺麗にしても index の機密語を検出する" "$(out_of "$r")"

echo "=== --tree: 追跡ファイル全体を見る ==="
# d.txt は index と作業ツリーが食い違っているので、--cached だけでは外せない
git -C "$repo" rm -qf --cached d.txt
rm -f "$repo/d.txt"
git -C "$repo" add -A
git -C "$repo" commit -q -m init
echo "secretcorp again" >"$repo/e.txt"
git -C "$repo" add e.txt
git -C "$repo" commit -q -m add-e
r=$(run_scan --tree)
check_exit 1 "$(exit_of "$r")" "--tree はコミット済みの機密語を検出する" "$(out_of "$r")"

echo "=== --worktree: ignoreされていない未追跡ファイルを見る ==="
echo "secretcorp untracked" >"$repo/untracked.txt"
r=$(run_scan --worktree)
check_exit 1 "$(exit_of "$r")" "--worktree は未追跡ファイルの機密語を検出する" "$(out_of "$r")"
check_contains "untracked.txt" "$(out_of "$r")" "未追跡ファイル名を出力する"
rm "$repo/untracked.txt"

echo "=== --worktree: ignore済み未追跡ファイルは見ない ==="
echo 'ignored.txt' >"$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m ignore-fixture
echo "secretcorp ignored" >"$repo/ignored.txt"
r=$(run_scan --worktree)
check_exit 1 "$(exit_of "$r")" "既存の追跡ファイルに機密語があれば検出したまま" "$(out_of "$r")"
case "$(out_of "$r")" in
  *ignored.txt*) ng "ignore済み未追跡ファイルは検査しない" "$(out_of "$r")" ;;
  *) ok "ignore済み未追跡ファイルは検査しない" ;;
esac

echo "=== 辞書ファイル自身は検査しない ==="
# 辞書はパターンの一覧なので必ず自分にマッチする。CI は .example を辞書として使うので実際に踏む
cp "$tmp/patterns.txt" "$repo/dict.txt"
git -C "$repo" add dict.txt
git -C "$repo" commit -q -m add-dict
r=$(SECRET_PATTERNS="$repo/dict.txt" run_scan --tree)
check_exit 1 "$(exit_of "$r")" "他ファイルの機密語は検出したまま" "$(out_of "$r")"
case "$(out_of "$r")" in
  *dict.txt*) ng "辞書ファイル自身を検査しない" "$(out_of "$r")" ;;
  *) ok "辞書ファイル自身を検査しない" ;;
esac

echo "=== バイナリファイルは中身を検査しない ==="
printf 'secretcorp\000\001\002binary\n' >"$repo/bin.dat"
git -C "$repo" add bin.dat
git -C "$repo" commit -q -m add-bin
r=$(run_scan --tree)
case "$(out_of "$r")" in
  *"[内容] bin.dat"*) ng "バイナリの中身を検査しない" "$(out_of "$r")" ;;
  *) ok "バイナリの中身を検査しない" ;;
esac

echo "=== symlink はリンク先の文字列を見る ==="
# 本体が追跡されていれば別途スキャンされるので、実体を二重に報告しない
ln -sf e.txt "$repo/alias.md"
git -C "$repo" add alias.md
git -C "$repo" commit -q -m add-link
r=$(run_scan --tree)
case "$(out_of "$r")" in
  *"[内容] alias.md"*) ng "symlink 経由で実体を二重報告しない" "$(out_of "$r")" ;;
  *) ok "symlink 経由で実体を二重報告しない" ;;
esac
ln -sf secretcorp-target.txt "$repo/bad-link.md"
git -C "$repo" add bad-link.md
r=$(run_scan --staged)
check_exit 1 "$(exit_of "$r")" "リンク先の文字列に機密語があれば検出する" "$(out_of "$r")"

echo "=== 引数 ==="
r=$(run_scan)
check_exit 2 "$(exit_of "$r")" "引数なしは exit 2" "$(out_of "$r")"
r=$(run_scan --bogus)
check_exit 2 "$(exit_of "$r")" "未知のモードは exit 2" "$(out_of "$r")"

echo "=== cross-repo設定はagent別配置でもignoreする ==="
for agent in agents claude codex; do
  path=".config/$agent/skills/cross-repo-investigate/repos.yml"
  if git -C "$REPO_ROOT" check-ignore -q "$path"; then
    ok "$agent 配置の repos.yml をignoreする"
  else
    ng "$agent 配置の repos.yml をignoreする"
  fi
done

echo "=== 辞書が無い場合 ==="
export SECRET_PATTERNS="$tmp/does-not-exist.txt"
r=$(run_scan --staged)
check_exit 0 "$(exit_of "$r")" "辞書が無ければ exit 0" "$(out_of "$r")"
check_contains "WARN" "$(out_of "$r")" "辞書が無ければ警告を出す"

echo "=== 辞書が空の場合 ==="
printf '# コメントだけ\n\n' >"$tmp/empty.txt"
export SECRET_PATTERNS="$tmp/empty.txt"
r=$(run_scan --staged)
check_exit 0 "$(exit_of "$r")" "辞書にパターンが無ければ exit 0" "$(out_of "$r")"

echo ""
echo "=== 結果 ==="
echo "PASS: $PASS  FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
fi
echo "全テスト成功"
exit 0
