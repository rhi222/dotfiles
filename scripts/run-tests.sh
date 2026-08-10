#!/bin/bash
# scripts/test-*.sh をまとめて実行する。
#
#   bash scripts/run-tests.sh        # 全部
#   bash scripts/run-tests.sh --ci   # `# ci-skip:` 宣言のあるものを飛ばす（CIから使う）
#
# 環境変数:
#   TEST_DIR      走査するディレクトリ（既定: このスクリプトの場所）
#   TEST_TIMEOUT  1本あたりの制限秒（既定: 300）
#
# CIで走らせられないテストは、テストファイル側の先頭付近に
#   # ci-skip: <理由>
# と書いて宣言する。除外リストをCI側に置くと、テストを足した人が
# 気付けないまま片方だけ更新されて食い違うため、宣言はテストに持たせる。
#
# ファイル名が test-*.sh に一致しないのは、自分自身を走査対象に含めないため。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${TEST_DIR:-$SCRIPT_DIR}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"

CI_MODE=0
[ "${1:-}" = "--ci" ] && CI_MODE=1

mapfile -t tests < <(find "$TEST_DIR" -maxdepth 1 -name 'test-*.sh' | sort)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "テストが1本も見つからない: $TEST_DIR" >&2
  exit 1
fi

passed=0
failed=0
skipped=0
failed_names=()

for t in "${tests[@]}"; do
  name="$(basename "$t")"

  # ci-skip の宣言はヘッダにだけ置く（本文中の同名文字列を拾わないよう先頭20行に限る）
  if [ "$CI_MODE" -eq 1 ] && reason=$(head -20 "$t" | grep -m1 -oP '(?<=# ci-skip:).*'); then
    echo "SKIP  $name —${reason}"
    skipped=$((skipped + 1))
    continue
  fi

  if out=$(timeout "$TEST_TIMEOUT" bash "$t" 2>&1); then
    echo "PASS  $name"
    passed=$((passed + 1))
  else
    rc=$?
    if [ "$rc" -eq 124 ]; then
      echo "TIMEOUT  $name（${TEST_TIMEOUT}秒で打ち切り）"
    else
      echo "FAIL  $name（exit $rc）"
    fi
    # 失敗したものだけ出力を見せる。全部出すとCIログが読めなくなる
    sed 's/^/      | /' <<<"$out"
    failed=$((failed + 1))
    failed_names+=("$name")
  fi
done

echo "---"
echo "pass: $passed 件 / fail: $failed 件 / skip: $skipped 件"

if [ "$failed" -gt 0 ]; then
  echo "失敗: ${failed_names[*]}"
  exit 1
fi
exit 0
