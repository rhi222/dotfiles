#!/bin/bash
# リポジトリが追跡しているシェルスクリプトを検査する。
#   *.sh   : shellcheck + shfmt
#   *.fish : fish -n（構文チェックのみ。fish に整形系の CLI は無い）
#
#   bash scripts/lint.sh        # 検査のみ（CIと同じ）
#   bash scripts/lint.sh --fix  # shfmt の整形を実際に適用
#
# 依存: shellcheck / shfmt（どちらも mise の aqua バックエンドで管理）、fish
#
# 環境変数:
#   LINT_REPO_ROOT  検査するリポジトリのルート（テストで差し替える）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${LINT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

# 対象は git 基準で「自分が保守する *.sh」全部。find で列挙すると tmux/yazi の
# プラグインや gh skill が持ち込む第三者のスクリプトまで拾ってしまう
# （実測で追跡65本に対しディスク上は144本）。ignore 済み＝自分が保守しない、で切れる。
#
# --others も含めるのは、まだ add していない新規スクリプトを検査対象にするため。
# --cached だけだと、書いたばかりのファイルが commit するまでローカルで検査されず、
# CI（checkout 後は追跡済み）で初めて落ちることになる。
#
# skills-vendor/ は除外する。**vendored な外部 skill は追跡しているが自分は保守しない。**
# 上の「ignore 済み＝自分が保守しない」という前提の唯一の例外で、除外しないと
# 第三者の .sh が shellcheck / shfmt に掛かって lint.yml が落ちる。
mapfile -t files < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.sh' ':!:.config/claude/skills-vendor/**' |
    xargs -0 -n1 printf '%s/%s\n' "$REPO_ROOT" | sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "検査対象の .sh が無い" >&2
  exit 1
fi

rc=0

echo "=== shellcheck ==="
# -x: source されるファイルも追跡 / SCRIPTDIR: source= の相対パスを各スクリプト基準で解決
#
# **tests/<domain>/ からの source を解決できるよう SCRIPTDIR/../../scripts も見る。**
# テストは `source "$SCRIPTS_DIR/lib/x.sh"` の形で呼ぶが、shellcheck は変数を
# 展開できず末尾の `lib/x.sh` をスクリプト基準で探す。テストが scripts/ 直下に
# あった頃はそれで当たっていたが、tests/ へ移すと外れて SC1091 になる。
if ! shellcheck -x --source-path=SCRIPTDIR:SCRIPTDIR/../../scripts "${files[@]}"; then
  rc=1
fi

echo "=== shfmt ==="
# -i 2: 2スペースインデント / -ci: case 分岐もインデント（既存スタイルに合わせる）
if [ "$FIX" -eq 1 ]; then
  shfmt -w -i 2 -ci "${files[@]}"
elif ! shfmt -d -i 2 -ci "${files[@]}"; then
  rc=1
fi

# .fish は shellcheck も shfmt も読めないので、fish 自身の構文チェックに掛ける。
#
# **これが無いと conf.d のタイポはシェル起動時まで発覚しない。** lint.yml は
# paths に **.fish を持っていて .fish の変更で発火するのに、走るのはテストを
# 持つ一部の関数のテストだけだった。
#
# 対象の集め方は .sh と揃える（追跡 + 未追跡、ignore 済みと skills-vendor は除外）。
mapfile -t fish_files < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.fish' ':!:.config/claude/skills-vendor/**' |
    xargs -0 -r -n1 printf '%s/%s\n' "$REPO_ROOT" | sort -u
)

echo "=== fish -n ==="
if [ "${#fish_files[@]}" -eq 0 ]; then
  # .sh は0本ならエラーにするが、.fish は0本でも正常（fish を使わない構成もありうる）
  echo "検査対象の .fish が無い"
elif ! command -v fish >/dev/null 2>&1; then
  # fish が無いだけで lint 全体を落とすと、fish を使わない端末で commit できなくなる
  echo "fish が無いため skip（${#fish_files[@]} 件）"
else
  # `fish -n a.fish b.fish` は1本目しか検査しない（2本目以降は $argv になる）。
  # 1本 2ms なので全部で 0.1 秒程度、直列で足りる。
  for f in "${fish_files[@]}"; do
    if ! fish -n "$f"; then
      echo "  syntax error: $f" >&2
      rc=1
    fi
  done
fi

if [ "$rc" -eq 0 ]; then
  echo "lint OK"
else
  echo "lint FAILED"
fi
exit "$rc"
