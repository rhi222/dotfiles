#!/bin/bash
# リポジトリ内から参照されている scripts/ 配下のパスが実在するか検査する。
#
#   bash scripts/ref-check.sh
#
# 例外は scripts/ref-check-allow.txt で宣言する（書式は1行1パス、glob 可）。
#
# **既存のどの検査にも掛からない層を埋める。** lint.sh は shell の中身、
# run-tests.sh は各スクリプトの振る舞い、doc-budget.sh は行数しか見ない。
# 一方 scripts/ 配下のパスは AGENTS.md の表・docs・Claude skill 本文・
# herdr の config.toml・crontab 行・dotfilesLink.sh から**散文として**
# 参照されていて（実測で prod 228件 / test 67件）、ここが壊れても
# 呼ばれた瞬間まで誰も気付かない。cron と hook からの参照は黙って失敗する。
#
# 参照の書き方は1つではないので、次を同じ実体として扱う。
#   scripts/example.sh / $DOTFILES_DIR/scripts/example.sh
#   $HOME/scripts/example.sh / ~/scripts/example.sh
#     （~/scripts は repo の scripts/ への symlink）
#   $REPO_ROOT/scripts/example.sh
#   $SCRIPT_DIR/example.sh（参照元のディレクトリ基準で解く）
#
# **逆に拾ってはいけないものが2つある。** `.config/herdr/scripts/status.sh`
# などの同名の別ディレクトリと、`$REPO/scripts/...`（テスト内の mktemp した
# 一時 repo を指す）。どちらも拾うと恒久的に赤くなり、検査ごと無視される。
#
# 環境変数:
#   REF_CHECK_REPO  検査するリポジトリのルート（テストで差し替える）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REF_CHECK_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ALLOW="$REPO_ROOT/scripts/ref-check-allow.txt"

# git を走査に使うので、リポジトリでなければ何もせず通す。**検査が
# bootstrap を壊すほうが、参照の取りこぼしより害が大きい**（doc-budget と同じ判断）。
if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ref-check: git リポジトリでないため skip: $REPO_ROOT"
  exit 0
fi

# 実在しなくてよいパスの宣言。allowlist は「例外」なので、無い環境では
# 全件を検査する（doc-budget と違い、無いことを skip の理由にしない）。
allow_patterns=()
if [ -f "$ALLOW" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] && allow_patterns+=("$line")
  done <"$ALLOW"
fi

is_allowed() {
  local path="$1" pat
  for pat in ${allow_patterns+"${allow_patterns[@]}"}; do
    # shellcheck disable=SC2053  # glob として比較したいので右辺はクォートしない
    [[ $path == $pat ]] && return 0
  done
  return 1
}

# **走査は git grep 1回に畳む。** ファイル単位で grep を回した初版は実 repo で
# 8.4秒かかった（500ファイル×4プロセス）。git grep は追跡ファイルと未追跡
# （ignore を除く）をまとめて1プロセスで見るので 0.03秒で終わる。
gg() {
  git -C "$REPO_ROOT" grep -I --no-color -noE --untracked -e "$1" -- . 2>/dev/null
}

# 出力はどれも `<file>:<行番号>:<参照>` の形に揃える。
scan() {
  # prefix 付きの形。$REPO は含めない（テスト内の mktemp した一時 repo を指すため）
  gg '(\$DOTFILES_DIR|\$REPO_ROOT|\$\{HOME\}|\$HOME|~)/scripts/[A-Za-z0-9._/-]+' |
    sed -E 's|(^[^:]+:[0-9]+:).*/scripts/|\1scripts/|'

  # $SCRIPT_DIR は参照元のディレクトリ基準なので、正規化はループ側で行う
  gg '\$SCRIPT_DIR/[A-Za-z0-9._/-]+'

  # 素の形。直前が [A-Za-z0-9._/-] のものは別ディレクトリの scripts/ なので拾わない
  gg '(^|[^A-Za-z0-9._/-])scripts/[A-Za-z0-9._/-]+' |
    sed -E 's|(^[^:]+:[0-9]+:).*(scripts/)|\1\2|'
}

violations=0
declare -A seen=()

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  lineno="${rest%%:*}"
  ref="${rest#*:}"

  # allowlist 自身は参照ではなくパターンの宣言。走査すると
  # `scripts/worktree-init.d*` のような宣言そのものを dangling として報告する
  [ "$file" = "scripts/ref-check-allow.txt" ] && continue

  # $SCRIPT_DIR は参照元のディレクトリで解く。**テストを tests/<domain>/ へ
  # 移すと基準が変わるので、移動で壊れる参照の本体はここ**
  case "$ref" in
    '$SCRIPT_DIR/'*)
      base="$(dirname "$file")"
      ref="${ref#\$SCRIPT_DIR/}"
      [ "$base" = "." ] || ref="$base/$ref"
      ;;
  esac

  # 末尾の / は落として実体（ディレクトリ）を見る。glob を含む参照は
  # `scripts/test-*.sh` → `scripts/test-` のように切れた残骸になるので、
  # 末尾が - または . のものは参照ではないと判断して捨てる
  ref="${ref%/}"
  case "$ref" in
    *- | *.) continue ;;
  esac

  [ -n "${seen[$ref]+x}" ] && continue
  [ -e "$REPO_ROOT/$ref" ] && continue
  is_allowed "$ref" && continue

  seen[$ref]=1
  echo "ref-check: 参照先が無い: $ref"
  echo "    $file:$lineno"
  violations=$((violations + 1))
done < <(scan)

if [ "$violations" -gt 0 ]; then
  echo
  echo "ref-check: $violations 件の参照が壊れている。"
  echo "  実在しなくてよいものは scripts/ref-check-allow.txt に宣言する。"
  echo "  例示やテストのフィクスチャなら、架空名を example* に寄せる（既に許可済み）。"
  exit 1
fi

echo "ref-check: OK"
