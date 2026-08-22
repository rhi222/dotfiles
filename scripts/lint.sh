#!/bin/bash
# リポジトリが追跡しているシェルスクリプトを検査する。
#   *.sh   : shellcheck + shfmt
#   *.md   : rumdl
#   *.lua  : stylua + LuaLS CLI
#   *.fish : fish -n + fish_indent
#   *.yml  : YAML としてパースできるか（整形はしない）
#
#   bash scripts/lint.sh        # 検査のみ（CIと同じ）
#   bash scripts/lint.sh --fix  # shfmt の整形を実際に適用
#
# 依存: shellcheck / shfmt / rumdl / stylua / lua-language-server（miseで管理）、fish
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
    xargs -0 -n1 printf '%s/%s\n' "$REPO_ROOT" |
    while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done | sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "検査対象の .sh が無い" >&2
  exit 1
fi

rc=0

echo "=== shellcheck ==="
# -x: source されるファイルも追跡 / SCRIPTDIR: source= の相対パスを各スクリプト基準で解決
#
# **tests/<feature>/ からの source を解決できるよう SCRIPTDIR/../../scripts も見る。**
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

# MarkdownもShellと同じく、自分が保守する追跡fileと未追跡fileだけを対象にする。
# vendored skillはupstreamの書式を保つため除外する。
mapfile -t markdown_files < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.md' ':!:.config/claude/skills-vendor/**' |
    xargs -0 -r -n1 printf '%s/%s\n' "$REPO_ROOT" |
    while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done | sort -u
)

echo "=== rumdl ==="
if [ "${#markdown_files[@]}" -eq 0 ]; then
  echo "検査対象の .md が無い"
elif ! rumdl check --config "$REPO_ROOT/.rumdl.toml" "${markdown_files[@]}"; then
  rc=1
fi

mapfile -t lua_files < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.lua' ':!:.config/claude/skills-vendor/**' |
    xargs -0 -r -n1 printf '%s/%s\n' "$REPO_ROOT" |
    while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done | sort -u
)

echo "=== stylua ==="
if [ "${#lua_files[@]}" -eq 0 ]; then
  echo "検査対象の .lua が無い"
elif [ "$FIX" -eq 1 ]; then
  stylua "${lua_files[@]}"
elif ! stylua --check "${lua_files[@]}"; then
  rc=1
fi

echo "=== LuaLS ==="
if [ "${#lua_files[@]}" -eq 0 ]; then
  echo "検査対象の .lua が無い"
else
  lua_check_dir=$(mktemp -d)
  if ! lua-language-server \
    --check="$REPO_ROOT" \
    --checklevel=Warning \
    --check_format=pretty \
    --configpath="$REPO_ROOT/.config/nvim/.luarc.json" \
    --metapath="$lua_check_dir/meta" \
    --logpath="$lua_check_dir/log"; then
    rc=1
  fi
  rm -rf -- "$lua_check_dir"
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
    xargs -0 -r -n1 printf '%s/%s\n' "$REPO_ROOT" |
    while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done | sort -u
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

echo "=== fish_indent ==="
if [ "${#fish_files[@]}" -eq 0 ]; then
  echo "検査対象の .fish が無い"
elif ! command -v fish_indent >/dev/null 2>&1; then
  echo "fish_indent が無いため skip（${#fish_files[@]} 件）"
elif [ "$FIX" -eq 1 ]; then
  fish_indent --write "${fish_files[@]}"
elif ! fish_indent --check "${fish_files[@]}"; then
  rc=1
fi

echo "=== yaml ==="
# **shfmt を .yml へ誤って掛けた事故の再発防止。** shfmt は YAML を shell として
# パースしてインデントを全部潰すが、それでも exit 0 で返る。lint.sh は .sh しか
# 見ていなかったので pre-commit も CI も素通りし、壊れた workflow を push して
# 初めて「workflow file issue」で気付いた。
#
# **整形はしない。** クォートやコメント位置の流儀に手を入れる必要はなく、
# 見たいのは「構造が壊れていないか」だけ。
mapfile -t yaml_files < <(
  git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard \
    '*.yml' '*.yaml' ':!:.config/claude/skills-vendor/**' |
    xargs -0 -r -n1 printf '%s/%s\n' "$REPO_ROOT" |
    while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done | sort -u
)
# **PATH の python3 だけを見ない。** CI の runner は PATH 先頭に tool cache の
# python3 を持っており、apt の python3-yaml（/usr/bin/python3 側に入る）が
# 見えない。それで CI だけ YAML を skip して通った。
yaml_py=""
for py in python3 /usr/bin/python3 python; do
  command -v "$py" >/dev/null 2>&1 || continue
  if "$py" -c 'import yaml' 2>/dev/null; then
    yaml_py="$py"
    break
  fi
done

if [ "${#yaml_files[@]}" -eq 0 ]; then
  echo "検査対象の .yml が無い"
elif [ -z "$yaml_py" ]; then
  # fish と同じ扱い。パーサが無いだけで commit できなくなるのは避ける
  echo "PyYAML を持つ python が無いため skip（${#yaml_files[@]} 件）"
else
  for f in "${yaml_files[@]}"; do
    if ! "$yaml_py" -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f"; then
      echo "  parse error: $f" >&2
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
