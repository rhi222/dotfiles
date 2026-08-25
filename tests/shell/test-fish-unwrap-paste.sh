#!/bin/bash
# fish関数 __unwrap_wrapped_text のユニットテスト
#
# 端末に表示された「本来1行」のテキストをコピーすると改行が混入する。混入の仕方は2種類あり、
# 連結の仕方が逆になる。
#
#   ① アプリ側の折返し（Claude Code のコードブロックなど）
#      描画幅で「単語境界」を切り、継続行に自前のインデントを付けて出力する。
#      改行は端末バッファ上の本物の改行なので、コピー機構では復元できない。
#      → 継続行は先頭空白を落として **空白1個** で連結する。
#
#   ② 端末のソフト折返し
#      ペイン幅でトークンの途中を切る。継続行にインデントは付かない。
#      → **連結子なし** でつなぐ。
#
# 見分けるのは「継続行が空白で始まるか」だけで足りる。①は必ず始まり、②は必ず始まらない。
# ペイン幅を知らなくても判定できるので、コピー元の端末幅に依存しない。
#
# 既知の限界: ②で折返し位置がちょうど空白に当たった場合、その空白は端末側の
# 行末トリムで失われるため復元できない（連結子なしで詰まる）。専用キー経由で
# コマンドラインに挿入するだけなので、実行前に目視で直せる範囲に留める。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$(cd "$REPO_ROOT/.config/fish/my/functions" && pwd)"
UNWRAP="$FUNC_DIR/__unwrap_wrapped_text.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
if [[ ! -f "$UNWRAP" ]]; then
  echo "ERROR: $UNWRAP が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

ok() {
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

ng() {
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
  echo "    expected: [$2]"
  echo "    actual:   [$3]"
}

# stdin のテキストを __unwrap_wrapped_text に通し、結果を返す。
# 関数定義だけを source し、対話セッションや設定ファイルには依存させない。
run_unwrap() {
  fish --no-config -c "source $UNWRAP; __unwrap_wrapped_text"
}

assert_unwrap() {
  local name="$1" input="$2" expected="$3"
  local actual
  actual="$(printf '%s' "$input" | run_unwrap)"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    ng "$name" "$expected" "$actual"
  fi
}

echo "=== __unwrap_wrapped_text ==="

assert_unwrap "1行はそのまま返す" \
  'echo hello' \
  'echo hello'

assert_unwrap "1行の前後の空白は落とす" \
  '  echo hello  ' \
  'echo hello'

# Claude Code がコードブロックを折返したケース。全行が同じインデントを持ち、
# 切れ目は単語境界（"| jq -r" の直後）にある。
assert_unwrap "アプリ折返し（継続行にインデント）は空白1個で連結する" \
  '  set creds (aws configure export-credentials --profile p --format json); and echo $creds | jq -r
  .SecretAccessKey' \
  'set creds (aws configure export-credentials --profile p --format json); and echo $creds | jq -r .SecretAccessKey'

# 端末がペイン幅で折返したケース。トークン "aws_secret_access_key" の途中で切れ、
# 継続行はインデントされない。
assert_unwrap "端末ソフト折返し（継続行にインデント無し）は連結子なしでつなぐ" \
  '  aws configure set aws_secre
t_access_key VALUE --profile p' \
  'aws configure set aws_secret_access_key VALUE --profile p'

assert_unwrap "URLのソフト折返しを連結子なしで復元する" \
  'https://github.com/rhi222/dotfiles/blob/main/docs/sessi
on-restore-strategy.md#L42' \
  'https://github.com/rhi222/dotfiles/blob/main/docs/session-restore-strategy.md#L42'

# 端末は行をパディングするので、行末の空白は連結前に必ず落とす。
assert_unwrap "行末のパディング空白を連結に持ち込まない" \
  'aws configure set aws_secre
t_access_key VALUE' \
  'aws configure set aws_secret_access_key VALUE'

assert_unwrap "タブのインデントも空白1個の連結として扱う" \
  'echo foo
	bar' \
  'echo foo bar'

assert_unwrap "3行以上でインデント有無が混在しても行ごとに判定する" \
  '  echo aaa bbb
  ccc ddd-ee
e fff' \
  'echo aaa bbb ccc ddd-eee fff'

assert_unwrap "末尾の空行を無視する" \
  '  echo foo
  bar

' \
  'echo foo bar'

assert_unwrap "途中の空行は連結の判定材料にしない" \
  '  echo foo

  bar' \
  'echo foo bar'

assert_unwrap "空入力は空文字を返す" \
  '' \
  ''

assert_unwrap "空白のみの入力は空文字を返す" \
  '
  ' \
  ''

# 端末やアプリが CRLF で渡してくる場合でも CR を残さない。
assert_unwrap "CRLFのCRを残さない" \
  "$(printf 'echo foo\r\n  bar\r\n')" \
  'echo foo bar'

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
