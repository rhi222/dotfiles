#!/bin/bash
# 社内固有情報がリポジトリに入るのを防ぐスキャナ。
#
#   bash scripts/secret-scan.sh --staged  # ステージ済みの内容を検査（pre-commit hook から）
#   bash scripts/secret-scan.sh --tree    # 追跡ファイル全体を検査（CI から）
#
# 辞書は ~/.config/dotfiles/secret-patterns.txt。このリポジトリは public なので
# 辞書そのものはリポジトリに置かない（scripts/secret-patterns.txt.example が雛形）。
#
# 辞書が無い場合は警告して通す。新環境で dotfilesLink.sh を走らせる前に
# commit できなくなるのを避けるため。
#
# 環境変数:
#   SECRET_PATTERNS - 辞書のパス（テスト用オーバーライド）
set -uo pipefail

PATTERNS="${SECRET_PATTERNS:-$HOME/.config/dotfiles/secret-patterns.txt}"

usage() {
  echo "使い方: secret-scan.sh <--staged|--tree>" >&2
}

mode="${1:-}"
if [ "$mode" != "--staged" ] && [ "$mode" != "--tree" ]; then
  usage
  exit 2
fi

if [ ! -f "$PATTERNS" ]; then
  echo "[WARN] 機密語辞書がありません: $PATTERNS" >&2
  echo "       scripts/secret-patterns.txt.example を参考に作成してください。" >&2
  echo "       検査せずに続行します。" >&2
  exit 0
fi

# コメントと空行を落として ERE の選択肢に畳む
re=$(grep -vE '^[[:space:]]*(#|$)' "$PATTERNS" | paste -sd'|')
if [ -z "$re" ]; then
  echo "[WARN] 辞書にパターンがありません: $PATTERNS" >&2
  exit 0
fi

# 検査対象のパス一覧。--staged は index、--tree は追跡ファイル全体
if [ "$mode" = "--staged" ]; then
  mapfile -t paths < <(git diff --cached --name-only --diff-filter=ACMR)
else
  mapfile -t paths < <(git ls-files)
fi

if [ "${#paths[@]}" -eq 0 ]; then
  exit 0
fi

found=0
report() {
  if [ "$found" -eq 0 ]; then
    echo "" >&2
    echo "社内固有情報が検出されました。" >&2
    echo "" >&2
    found=1
  fi
}

# 辞書ファイル自身の絶対パス。自分を検査対象から外すために使う
patterns_real=$(realpath "$PATTERNS" 2>/dev/null || echo "$PATTERNS")

for path in "${paths[@]}"; do
  [ -z "$path" ] && continue

  # 辞書は検査しない。パターンの一覧なので必ず自分にマッチする
  # （CI は scripts/secret-patterns.txt.example を辞書として使うため実際に踏む）
  if [ "$(realpath "$path" 2>/dev/null || echo "$path")" = "$patterns_real" ]; then
    continue
  fi

  # パス名そのものの検査。ファイル名に社内システム名が入ることがあり、
  # 中身を置換してもファイル名は残る
  if printf '%s' "$path" | grep -qE "$re"; then
    report
    echo "  [パス名] $path" >&2
  fi

  # 中身の検査。
  # -I でバイナリを除外する（画像等。-a だと中身がそのまま出力に混ざる）。
  # symlink は本体ではなくリンク先の文字列を見る。git が保存しているのもそれで、
  # 本体が追跡されていれば別途スキャンされる（CLAUDE.md -> AGENTS.md など）。
  hits=""
  if [ "$mode" = "--staged" ]; then
    hits=$(git show ":$path" 2>/dev/null | grep -InE "$re" | head -5)
  elif [ -L "$path" ]; then
    hits=$(readlink "$path" | grep -InE "$re" | head -5)
  elif [ -f "$path" ]; then
    hits=$(grep -InE "$re" "$path" | head -5)
  fi

  if [ -n "$hits" ]; then
    report
    echo "  [内容] $path" >&2
    printf '%s\n' "$hits" | sed 's/^/      /' >&2
  fi
done

if [ "$found" -eq 1 ]; then
  echo "" >&2
  echo "対処:" >&2
  echo "  - 値そのものは ~/.claude/local-context.md へ移す" >&2
  echo "  - 例示・テストデータは example-org / example-repo などの架空名に置き換える" >&2
  echo "  - 意図的に通す場合のみ git commit --no-verify（原則使わない）" >&2
  exit 1
fi

exit 0
