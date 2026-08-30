#!/bin/bash
# 自分が保守する Markdown を Prettier で検査または整形する。
#   markdown-format.sh           作業ツリーを検査
#   markdown-format.sh --staged  index の内容を検査（pre-commit向け）
#   markdown-format.sh --fix     作業ツリーを整形
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${MARKDOWN_FORMAT_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CONFIG="$REPO_ROOT/.prettierrc.json"
MODE="${1:-check}"

case "$MODE" in
  check | --fix | --staged) ;;
  *)
    echo "usage: $0 [--fix|--staged]" >&2
    exit 2
    ;;
esac

if ! command -v prettier >/dev/null 2>&1; then
  echo "ERROR: prettier が見つかりません" >&2
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "ERROR: Prettier設定が見つかりません: $CONFIG" >&2
  exit 1
fi

if [ "$MODE" = "--staged" ]; then
  mapfile -d '' -t files < <(
    git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR -z -- \
      '*.md' ':(exclude).config/agents/skills-vendor/**' ':(exclude)plugins/**'
  )

  [ "${#files[@]}" -gt 0 ] || exit 0

  input=$(mktemp)
  output=$(mktemp)
  trap 'rm -f -- "$input" "$output"' EXIT
  rc=0

  # 作業ツリーではなくindexの内容を検査する。部分stage中でもcommit対象だけを
  # 判定し、未stageの編集を誤って検査または書き換えないため。
  for file in "${files[@]}"; do
    index_entry=$(git -C "$REPO_ROOT" ls-files -s -- "$file")
    [ "${index_entry%% *}" = "120000" ] && continue
    if ! git -C "$REPO_ROOT" show ":$file" >"$input"; then
      echo "ERROR: stage済みMarkdownを読めません: $file" >&2
      rc=1
      continue
    fi
    if ! prettier --config "$CONFIG" --stdin-filepath "$REPO_ROOT/$file" <"$input" >"$output"; then
      echo "ERROR: Prettierの実行に失敗しました: $file" >&2
      rc=1
      continue
    fi
    if ! cmp -s "$input" "$output"; then
      echo "Prettierによる整形が必要: $file" >&2
      rc=1
    fi
  done
  if [ "$rc" -ne 0 ]; then
    echo "整形する: bash scripts/repository/markdown-format.sh --fix" >&2
  fi
  exit "$rc"
fi

mapfile -d '' -t candidates < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.md' ':!:.config/agents/skills-vendor/**' ':!:plugins/**'
)

files=()
for file in "${candidates[@]}"; do
  [ -f "$REPO_ROOT/$file" ] || continue
  [ -L "$REPO_ROOT/$file" ] && continue
  files+=("$file")
done

[ "${#files[@]}" -gt 0 ] || {
  echo "検査対象の .md が無い"
  exit 0
}

for i in "${!files[@]}"; do
  files[i]="$REPO_ROOT/${files[i]}"
done

if [ "$MODE" = "--fix" ]; then
  prettier --config "$CONFIG" --write "${files[@]}"
else
  prettier --config "$CONFIG" --check "${files[@]}"
fi
