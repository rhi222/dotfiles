#!/bin/bash
# ref-check.sh のユニットテスト
#
# scripts/ 配下のパスは AGENTS.md の表・docs・Claude skill 本文・herdr の
# config.toml・cron 行・dotfilesLink.sh から**散文として**参照されている。
# これらは呼ばれた瞬間まで壊れていることが分からず、
# cron や hook からの参照は**黙って**失敗する。テストとリンタは自分の中身しか
# 見ないので、この層を埋めるのが ref-check.sh。
#
# 参照の書き方は1つではない。`bash scripts/example.sh`、`$DOTFILES_DIR/scripts/example.sh`、
# `$HOME/scripts/example.sh`（旧名はcompat manifestからHOME側へlink）、
# 同一ディレクトリ内の `$SCRIPTS_DIR/example.sh` が実在する。**逆に
# `.config/herdr/scripts/status.sh` は別物**なので、これを拾うと恒久的に赤くなる。
#
# REPO を差し替えて実行する。ネットワークにも実環境にも触らない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/repository/ref-check.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# 参照される側の実体を置く
make_target() {
  mkdir -p "$(dirname "$REPO/$1")"
  echo '#!/bin/bash' >"$REPO/$1"
}

# 参照する側のファイルを置く
make_referrer() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$REPO/$path")"
  printf '%s\n' "$@" >"$REPO/$path"
}

allow() {
  mkdir -p "$REPO/scripts/repository"
  printf '%s\n' "$@" >"$REPO/scripts/repository/ref-check-allow.txt"
}

# ref-check.sh は引数を取らない
run_check() {
  env REF_CHECK_REPO="$REPO" bash "$TARGET" 2>&1
}

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         expected: $expected"
    echo "         actual  : $actual"
  fi
}

has() { grep -q -- "$1" <<<"$2" && echo yes || echo no; }

echo "== 参照が全部生きているとき =="

setup
make_target scripts/example-alpha.sh
make_referrer AGENTS.md '確認は `bash scripts/example-alpha.sh`。'
out=$(run_check)
rc=$?
check "全部生きていれば成功で返す" "0" "$rc"
check "OK を伝える" "yes" "$(has 'ref-check: OK' "$out")"
teardown

echo "== 公開コマンド索引 =="

setup
make_target scripts/example/tool.sh
make_referrer docs/scripts-command-index.md '# scripts'
out=$(run_check)
rc=$?
check "索引から漏れた公開コマンドを落とす" "1" "$rc"
check "漏れたコマンドを名指しする" "yes" "$(has 'scripts/example/tool.sh' "$out")"
make_referrer docs/scripts-command-index.md '# scripts' '`scripts/example/tool.sh`'
out=$(run_check)
rc=$?
check "公開コマンドが索引にあれば通す" "0" "$rc"
teardown

echo "== dangling を見つけたとき =="

setup
make_target scripts/example-alpha.sh
make_referrer AGENTS.md '確認は `bash scripts/example-alpha.sh`。' \
  '掃除は `bash scripts/example-ghost.sh`。'
out=$(run_check)
rc=$?
check "dangling があれば失敗で返す" "1" "$rc"
check "壊れたパスを名指しする" "yes" "$(has 'scripts/example-ghost.sh' "$out")"
check "参照元を file:line で出す" "yes" "$(has 'AGENTS.md:2' "$out")"
check "生きている参照は出さない" "no" "$(has 'scripts/example-alpha.sh' "$out")"
teardown

echo "== 同名の別ディレクトリを巻き込まない =="

setup
# .config/herdr/scripts/ と .config/claude/scripts/ は repo 直下の scripts/ とは別物。
# ここを拾うと恒久的に赤くなり、ref-check ごと無視されるようになる
make_referrer .config/herdr/config.toml \
  'command = "bash ~/.config/herdr/scripts/status.sh"'
make_referrer AGENTS.md '1行目は `.config/claude/scripts/statusline-model.sh` を呼ぶ。'
out=$(run_check)
rc=$?
check "別ディレクトリの scripts/ は対象外" "0" "$rc"
check "status.sh を dangling にしない" "no" "$(has 'status.sh' "$out")"
check "statusline-model.sh を dangling にしない" "no" "$(has 'statusline-model' "$out")"
teardown

echo "== パスの書き方を正規化する =="

setup
make_target scripts/example-alpha.sh
# HOME側の旧名はcompat manifestで正規entrypointへ解決する。
# ~ はフィクスチャ本文として literal で書くので展開させない
# shellcheck disable=SC2088
make_referrer docs/bootstrap.md \
  'bash "$DOTFILES_DIR/scripts/example-alpha.sh"' \
  '$HOME/scripts/example-alpha.sh' \
  '~/scripts/example-alpha.sh' \
  '"$REPO_ROOT/scripts/example-alpha.sh"'
out=$(run_check)
rc=$?
check "既知の prefix 付きでも実在と判定する" "0" "$rc"
teardown

setup
# prefix 付きでも dangling なら落とす（正規化が「常に通す」になっていないこと）
make_referrer docs/bootstrap.md 'bash "$DOTFILES_DIR/scripts/example-ghost.sh"'
out=$(run_check)
rc=$?
check "prefix 付きの dangling は落とす" "1" "$rc"
check "正規化後のパスで報告する" "yes" "$(has 'scripts/example-ghost.sh' "$out")"
teardown

echo "== \$SCRIPT_DIR は参照元のディレクトリで解く =="

setup
make_target scripts/example-alpha.sh
make_target scripts/lib/example-helper.sh
make_referrer scripts/example-caller.sh \
  'source "$SCRIPT_DIR/lib/example-helper.sh"' \
  'bash "$SCRIPT_DIR/example-alpha.sh"'
out=$(run_check)
rc=$?
check "同一ディレクトリ基準で解決する" "0" "$rc"
teardown

setup
# テストを tests/<feature>/ へ移すと $SCRIPT_DIR の基準が変わる。**Phase 1 で
# 壊れるのはまさにこの参照**なので、ディレクトリ相対で解けていることを確かめる
make_target scripts/example-alpha.sh
make_referrer tests/worktree/test-example-alpha.sh 'TARGET="$SCRIPT_DIR/example-alpha.sh"'
out=$(run_check)
rc=$?
check "別ディレクトリからの \$SCRIPT_DIR は解決先が変わる" "1" "$rc"
check "解決後のパスで報告する" "yes" "$(has 'tests/worktree/example-alpha.sh' "$out")"
teardown

echo "== allowlist =="

setup
make_referrer scripts/example-audit.sh 'cat >"$d/scripts/example-run.sh" <<EOF'
allow '# フィクスチャ本文に出てくる架空のパス' 'scripts/example-run.sh'
out=$(run_check)
rc=$?
check "allowlist にあれば無視する" "0" "$rc"
teardown

setup
# 利用者が任意で置くフックは「無いのが既定」。glob で許す
make_referrer docs/worktree.md '`scripts/worktree-init.d/github.com/rhi222/dotfiles.sh`'
allow 'scripts/worktree-init.d/*'
out=$(run_check)
rc=$?
check "glob で許せる" "0" "$rc"
teardown

setup
# allowlist は「例外の宣言」なので、無い環境では全件を検査する。
# doc-budget と違い、無いことを skip の理由にしない
make_referrer AGENTS.md '`bash scripts/example-ghost.sh`'
out=$(run_check)
rc=$?
check "allowlist が無くても検査する" "1" "$rc"
teardown

echo "== 拡張子の取りこぼし =="

setup
# `secret-patterns.txt.example` を `.txt` で切ると、実在するのに
# dangling として報告される（実際に私の初版が踏んだ）
make_target scripts/example-patterns.txt.example
make_referrer dotfilesLink.sh 'cp "$DOTFILES_DIR/scripts/example-patterns.txt.example" "$p"'
out=$(run_check)
rc=$?
check "二重拡張子を取りこぼさない" "0" "$rc"
teardown

echo "== 走査対象 =="

setup
make_referrer AGENTS.md '`bash scripts/example-ghost.sh`'
printf 'AGENTS.md\n' >"$REPO/.gitignore"
out=$(run_check)
rc=$?
check "gitignore されたファイルは走査しない" "0" "$rc"
teardown

setup
make_target scripts/example-alpha.sh
# バイナリを掴んで誤検知しないこと。実 repo には zip や画像が入りうる
printf '\x00\x01scripts/example-ghost.sh\x00' >"$REPO/blob.bin"
out=$(run_check)
rc=$?
check "バイナリファイルは走査しない" "0" "$rc"
teardown

echo "== 読めないとき =="

setup
rm -rf "$REPO/.git"
out=$(run_check)
rc=$?
check "git リポジトリでなければ成功で返す" "0" "$rc"
check "skip したことを伝える" "yes" "$(has 'skip' "$out")"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
