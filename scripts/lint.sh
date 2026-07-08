#!/bin/bash
# scripts/ 配下のシェルスクリプトを shellcheck + shfmt で検査する。
#
#   bash scripts/lint.sh        # 検査のみ（CIと同じ）
#   bash scripts/lint.sh --fix  # shfmt の整形を実際に適用
#
# 依存: shellcheck / shfmt（どちらも mise の aqua バックエンドで管理）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# 対象: リポジトリ直下（dotfilesLink.sh 等）と scripts/ 配下
mapfile -t files < <(
  {
    find "$REPO_ROOT" -maxdepth 1 -name '*.sh'
    find "$SCRIPT_DIR" -name '*.sh'
  } | sort
)

rc=0

echo "=== shellcheck ==="
# -x: source されるファイルも追跡 / SCRIPTDIR: source= の相対パスを各スクリプト基準で解決
if ! shellcheck -x --source-path=SCRIPTDIR "${files[@]}"; then
  rc=1
fi

echo "=== shfmt ==="
# -i 2: 2スペースインデント / -ci: case 分岐もインデント（既存スタイルに合わせる）
if [ "$FIX" -eq 1 ]; then
  shfmt -w -i 2 -ci "${files[@]}"
elif ! shfmt -d -i 2 -ci "${files[@]}"; then
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "lint OK"
else
  echo "lint FAILED"
fi
exit "$rc"
