#!/bin/bash
# skill-add.sh の振る舞いのテスト（allowlist ゲート以外）
#
# owner allowlist の default-deny は test-claude-skills-allowlist.sh が
# skill-add.sh / setup-claude-skills.sh の両方について見ている。こちらは
# ゲートを通った後の「gh の呼び方」と「claude-skills.txt の書き方」を固定する。
#
# gh は PATH 前方の stub に差し替え、呼ばれた引数を GH_LOG に記録する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
TARGET="$SCRIPTS_DIR/skill-add.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
STUB_DIR=""
OWNERS=""
SKILLS=""
GH_LOG=""

setup() {
  TEST_DIR=$(mktemp -d)
  STUB_DIR="$TEST_DIR/bin"
  OWNERS="$TEST_DIR/trusted-owners.txt"
  SKILLS="$TEST_DIR/claude-skills.txt"
  GH_LOG="$TEST_DIR/gh.log"
  mkdir -p "$STUB_DIR"
  : >"$GH_LOG"
  printf 'anthropics\n' >"$OWNERS"
  : >"$SKILLS"

  cat >"$STUB_DIR/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 ${2:-}" in
  "--version ") echo "gh version 2.97.0 (2026-07-31)"; exit 0 ;;
  "auth status") exit 0 ;;
esac
exit "${GH_INSTALL_RC:-0}"
STUB
  chmod +x "$STUB_DIR/gh"
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

run_add() {
  env PATH="$STUB_DIR:$PATH" \
    TRUSTED_SKILL_OWNERS_FILE="$OWNERS" \
    CLAUDE_SKILLS_FILE="$SKILLS" \
    GH_LOG="$GH_LOG" \
    "$@" 2>&1
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

echo "== 引数の検査 =="

setup
out=$(run_add bash "$TARGET")
check "引数なしは usage で 2" "2" "$?"
check "usage を出す" "yes" "$(grep -q 'Usage: skill-add.sh' <<<"$out" && echo yes || echo no)"
teardown

setup
out=$(run_add bash "$TARGET" anthropics/skills)
check "引数1つは usage で 2" "2" "$?"
teardown

setup
out=$(run_add bash "$TARGET" anthropics/skills a b)
check "引数3つは usage で 2" "2" "$?"
teardown

setup
out=$(run_add bash "$TARGET" notarepo skill-creator)
check "owner/repo 形式でなければ 2" "2" "$?"
check "何が来たかを出す" "yes" "$(grep -q 'notarepo' <<<"$out" && echo yes || echo no)"
# 形式チェックは gh を呼ぶ前に済ませる
check "gh を呼ばない" "0" "$(wc -l <"$GH_LOG")"
teardown

echo "== agent ごとに install する =="

setup
out=$(run_add bash "$TARGET" anthropics/skills skill-creator)
check "既定は claude-code と codex の2回" "2" \
  "$(grep -c 'skill install' "$GH_LOG")"
check "claude-code に入れる" "yes" \
  "$(grep -q 'skill install anthropics/skills skill-creator --agent claude-code --scope user' "$GH_LOG" && echo yes || echo no)"
check "codex に入れる" "yes" \
  "$(grep -q 'skill install anthropics/skills skill-creator --agent codex --scope user' "$GH_LOG" && echo yes || echo no)"
teardown

setup
out=$(run_add SKILL_AGENTS="claude-code" bash "$TARGET" anthropics/skills skill-creator)
check "SKILL_AGENTS で絞れる" "1" "$(grep -c 'skill install' "$GH_LOG")"
teardown

setup
out=$(run_add GH_INSTALL_RC=1 bash "$TARGET" anthropics/skills skill-creator)
# set -e なので install の失敗でそこで止まる
check "install が失敗したら止まる" "1" "$?"
check "失敗したら宣言に追記しない" "" "$(cat "$SKILLS")"
teardown

echo "== claude-skills.txt への追記 =="

setup
out=$(run_add SKILL_AGENTS="claude-code" bash "$TARGET" anthropics/skills skill-creator)
check "宣言に1行足す" "anthropics/skills skill-creator" "$(cat "$SKILLS")"
teardown

setup
# 末尾に改行が無いファイル。そのまま追記すると前の行と繋がって1行が壊れる
printf 'anthropics/skills frontend-design' >"$SKILLS"
out=$(run_add SKILL_AGENTS="claude-code" bash "$TARGET" anthropics/skills skill-creator)
check "末尾に改行が無くても行を壊さない" "2" "$(wc -l <"$SKILLS")"
check "既存行が残る" "yes" \
  "$(grep -qx 'anthropics/skills frontend-design' "$SKILLS" && echo yes || echo no)"
check "新しい行が独立している" "yes" \
  "$(grep -qx 'anthropics/skills skill-creator' "$SKILLS" && echo yes || echo no)"
teardown

setup
printf 'anthropics/skills skill-creator\n' >"$SKILLS"
out=$(run_add SKILL_AGENTS="claude-code" bash "$TARGET" anthropics/skills skill-creator)
check "既に宣言済みなら重複させない" "1" "$(wc -l <"$SKILLS")"
# 宣言済み＝入れ直しの意図なので --force を付ける（gh は既存を上書きしない）
check "--force を付けて入れ直す" "yes" \
  "$(grep -q -- '--force' "$GH_LOG" && echo yes || echo no)"
check "宣言済みであることを伝える" "yes" \
  "$(grep -q 'already in' <<<"$out" && echo yes || echo no)"
teardown

setup
out=$(run_add SKILL_AGENTS="claude-code" bash "$TARGET" anthropics/skills 'git-commit@v1.2.0')
check "@version 付きも宣言に入る" "anthropics/skills git-commit@v1.2.0" "$(cat "$SKILLS")"
# 表示名からはバージョンを落とす（skill 名は git-commit）
check "skill 名から @version を落とす" "yes" \
  "$(grep -q 'Installed skill: git-commit ' <<<"$out" && echo yes || echo no)"
teardown

echo "== gh が無いとき =="

setup
# gh だけが引けない PATH を組む。/usr/bin をまるごと外すと dirname も grep も
# 消えてスクリプトが別の理由で落ちるので、必要なものだけ symlink で並べる。
# printf は bash 組み込みでもあるので type -P で外部の実体を引く
NOGH="$TEST_DIR/nogh"
mkdir -p "$NOGH"
for t in dirname grep tail wc printf cat; do
  ln -sf "$(type -P "$t")" "$NOGH/$t"
done
# 形式チェックと allowlist は通り、gh が無いところで落ちる
out=$(env PATH="$NOGH" TRUSTED_SKILL_OWNERS_FILE="$OWNERS" \
  CLAUDE_SKILLS_FILE="$SKILLS" /bin/bash "$TARGET" anthropics/skills skill-creator 2>&1)
check "gh が無ければ 1" "1" "$?"
check "理由を出す" "yes" "$(grep -q 'gh CLI not found' <<<"$out" && echo yes || echo no)"
check "宣言に追記しない" "" "$(cat "$SKILLS")"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
