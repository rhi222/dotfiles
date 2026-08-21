#!/bin/bash
# エージェント向け文書の行数予算を検査する。
#
#   bash scripts/doc-budget.sh            # 作業ツリーを検査
#   bash scripts/doc-budget.sh --staged   # ステージ済みの内容を検査（pre-commit hook から）
#
# 予算は scripts/doc-budget.txt で宣言する。書式は1行1ファイルで
#   <path> <ファイル全体の行数上限> <1セクションの行数上限>
#
# **散文の規約が守られなかったので機械化した**（pr-base-guard と同じ理由）。
# AGENTS.md は冒頭で「各機能の表と、選択を左右する数個の理由だけを置く」と
# 宣言しているのに、4月の 6KB から8月に 66KB まで増え、圧縮を2回やって
# 2回とも数日で戻った。宣言は commit の瞬間のチェックではないので、
# そこにゲートを置く。
#
# 環境変数:
#   DOC_BUDGET_REPO  検査するリポジトリのルート（テストで差し替える）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${DOC_BUDGET_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DECL="$REPO_ROOT/scripts/doc-budget.txt"

mode="${1:-}"
if [ -n "$mode" ] && [ "$mode" != "--staged" ]; then
  echo "使い方: doc-budget.sh [--staged]" >&2
  exit 2
fi

# 宣言リストが無い環境では警告して通す。dotfilesLink.sh を走らせる前の新環境で
# commit できなくなるのを避ける（secret-scan.sh の辞書と同じ判断）。
if [ ! -f "$DECL" ]; then
  echo "doc-budget: 宣言リストが無いため skip: scripts/doc-budget.txt"
  exit 0
fi

violations=0

# 1ファイル分の予算を検査して、超過を報告する。
check_file() {
  local path="$1" max_total="$2" max_section="$3"
  local content

  # 対象が読めなければ skip して通す。**pre-commit を壊すほうが、
  # 予算の取りこぼしより害が大きい。** 宣言の typo を黙って飲むことになるが、
  # 宣言リストは1行3語なので目視で足りる。
  if [ "$mode" = "--staged" ]; then
    if ! content=$(git -C "$REPO_ROOT" show ":$path" 2>/dev/null); then
      echo "doc-budget: index に無いため skip: $path"
      return 0
    fi
  else
    if [ ! -f "$REPO_ROOT/$path" ]; then
      echo "doc-budget: ファイルが無いため skip: $path"
      return 0
    fi
    content=$(cat "$REPO_ROOT/$path")
  fi

  local total=0 sections=0 in_code=0
  local cur_name="" cur_lines=0
  local over_total=0
  local -a over_sections=()

  # セクション予算の判定。最初の見出しより前（h1 とリード文）は cur_name が
  # 空なので対象外になる。
  flush_section() {
    [ -z "$cur_name" ] && return 0
    sections=$((sections + 1))
    if [ "$cur_lines" -gt "$max_section" ]; then
      over_sections+=("$cur_name|$cur_lines")
    fi
  }

  while IFS= read -r line; do
    total=$((total + 1))

    # コードブロックの中は見出しと見なさない。**md の本文にはシェルの
    # コメント行がそのまま入る**（crontab の例など）ので、`^##` で素朴に
    # 切ると設定例をセクションとして拾ってしまう。
    case "$line" in
      '```'*) in_code=$((1 - in_code)) ;;
    esac

    # 区切りは `## ` と `### ` だけ。`#### ` は親セクションに含める
    # （AGENTS.md の「復元の進み具合を見る」がこれで、独立した機能ではない）。
    if [ "$in_code" -eq 0 ] && [[ "$line" =~ ^#{2,3}\  ]]; then
      flush_section
      cur_name="$line"
      cur_lines=1
      continue
    fi

    [ -n "$cur_name" ] && cur_lines=$((cur_lines + 1))
  done <<<"$content"
  flush_section

  [ "$total" -gt "$max_total" ] && over_total=1

  echo "$path: ${total}行 / ${sections}セクション"

  if [ "$over_total" -eq 1 ]; then
    echo "  NG  ファイル全体 ${total}/${max_total}行（$((total - max_total))行 超過）"
  else
    # **予算内でも余裕を出す。** 圧縮が進んだときに上限値を下げ忘れると
    # ratchet が効かなくなるので、毎回その場で見えるようにする。
    echo "  OK  ファイル全体 ${total}/${max_total}行（余裕 $((max_total - total))行）"
  fi

  local entry name lines
  for entry in ${over_sections[@]+"${over_sections[@]}"}; do
    name="${entry%|*}"
    lines="${entry##*|}"
    echo "  NG  $name  ${lines}行 > 上限 ${max_section}行"
  done

  violations=$((violations + over_total + ${#over_sections[@]}))
}

lineno=0
while IFS= read -r decl || [ -n "$decl" ]; do
  lineno=$((lineno + 1))
  # コメントと空行を飛ばす
  [[ "$decl" =~ ^[[:space:]]*(#|$) ]] && continue

  read -r path max_total max_section rest <<<"$decl"

  # **不正な宣言は落とす。** 対象が無いときと違い、これは宣言そのものが
  # 壊れている状態。黙って通すと検査が消えたことに気付けない。
  if [ -z "${max_section:-}" ] || [ -n "${rest:-}" ] ||
    ! [[ "$max_total" =~ ^[0-9]+$ ]] || ! [[ "$max_section" =~ ^[0-9]+$ ]]; then
    echo "doc-budget: 宣言が不正: scripts/doc-budget.txt:$lineno: $decl" >&2
    violations=$((violations + 1))
    continue
  fi

  check_file "$path" "$max_total" "$max_section"
done <"$DECL"

if [ "$violations" -eq 0 ]; then
  echo "doc-budget: OK"
  exit 0
fi

echo "doc-budget: FAILED (${violations}件)"
echo "  超過分は docs/ へ出すか圧縮する。上限値の変更は scripts/doc-budget.txt。"
exit 1
