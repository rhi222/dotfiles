#!/bin/bash
# リポジトリが追跡しているシェルスクリプトを shellcheck + shfmt で検査する。
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

# 対象は git が追跡している *.sh 全部。find で列挙すると
# tmux/yazi のプラグインや gh skill が持ち込む第三者のスクリプトまで拾ってしまう
# （実測で追跡65本に対しディスク上は144本）。ignore 済み＝自分が保守しない、で切れる。
mapfile -t files < <(git -C "$REPO_ROOT" ls-files -z '*.sh' | xargs -0 -n1 printf '%s/%s\n' "$REPO_ROOT" | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "検査対象の .sh が無い" >&2
  exit 1
fi

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
