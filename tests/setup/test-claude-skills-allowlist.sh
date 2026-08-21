#!/bin/bash
# owner allowlist ゲートのテスト。
# skill-add.sh と setup-claude-skills.sh の**両方**で塞がっていることを検証する。
# 片方だけだと bootstrap 経路（setup を直に叩く）から allowlist 外が入る。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
LIB="$SCRIPTS_DIR/lib/trusted-skill-owners.sh"
ADD="$SCRIPTS_DIR/skill-add.sh"
SETUP="$SCRIPTS_DIR/setup-claude-skills.sh"
OWNERS="$SCRIPTS_DIR/trusted-skill-owners.txt"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" name="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $name (expected=$expected, got=$actual)"
  fi
}

for f in "$LIB" "$OWNERS"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: $f が存在しません"
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== allowlist ファイルの中身 ==="
# 個人アカウントを入れないこと。ここに入れると人のレビューなしで毎日更新される
for owner in anthropics github vercel-labs; do
  TOTAL=$((TOTAL + 1))
  if grep -qxF "$owner" "$OWNERS"; then
    PASS=$((PASS + 1))
    echo "  PASS: $owner が入っている"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $owner が入っていない"
  fi
done
for owner in sanyuan0704 mattpocock browser-use; do
  TOTAL=$((TOTAL + 1))
  if grep -qxF "$owner" "$OWNERS"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $owner が入っている（vendoring 対象のはず）"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $owner は入っていない"
  fi
done
echo ""

echo "=== is_trusted_owner ==="
# shellcheck source=lib/trusted-skill-owners.sh
source "$LIB"

CUSTOM="$TMP/owners.txt"
cat >"$CUSTOM" <<'TXT'
# コメント行は無視する
anthropics

  github  
TXT

TOTAL=$((TOTAL + 1))
if TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" is_trusted_owner anthropics; then
  PASS=$((PASS + 1))
  echo "  PASS: allowlist 内は真"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: allowlist 内は真"
fi

TOTAL=$((TOTAL + 1))
if TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" is_trusted_owner github; then
  PASS=$((PASS + 1))
  echo "  PASS: 前後の空白は無視する"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: 前後の空白は無視する"
fi

TOTAL=$((TOTAL + 1))
if TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" is_trusted_owner someone; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: allowlist 外は偽"
else
  PASS=$((PASS + 1))
  echo "  PASS: allowlist 外は偽"
fi

# コメント行の中身を owner として拾わないこと
TOTAL=$((TOTAL + 1))
if TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" is_trusted_owner "コメント行は無視する"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: コメント行を owner として拾わない"
else
  PASS=$((PASS + 1))
  echo "  PASS: コメント行を owner として拾わない"
fi

# ファイルが無ければ拒否する（fail-closed）。
# secret-scan.sh の辞書とは逆に倒す。辞書不在で commit できないのは困るが、
# allowlist 不在で skill が入らないのは機能が欠けるだけで害がない
TOTAL=$((TOTAL + 1))
if TRUSTED_SKILL_OWNERS_FILE="$TMP/nope.txt" is_trusted_owner anthropics; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: allowlist ファイル不在なら拒否する"
else
  PASS=$((PASS + 1))
  echo "  PASS: allowlist ファイル不在なら拒否する"
fi
echo ""

echo "=== skill-add.sh のゲート ==="
# gh のスタブを置き、allowlist を通った場合に gh が呼ばれることも見る
BIN="$TMP/bin"
mkdir -p "$BIN"
GH_LOG="$TMP/gh.log"
: >"$GH_LOG"
# setup-claude-skills.sh は gh のバージョンと auth を先に見る。素朴に exit 0 する
# スタブだと prereq_fail で黙って exit 0 し、ゲートまで到達しない
cat >"$BIN/gh" <<STUB
#!/bin/bash
echo "\$*" >>"$GH_LOG"
case "\$1 \${2:-}" in
  "--version ")  echo "gh version 2.97.0 (2026-07-31)"; exit 0 ;;
  "auth status") exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"

SKILLS_COPY="$TMP/claude-skills.txt"
: >"$SKILLS_COPY"

out="$(env PATH="$BIN:$PATH" \
  TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" \
  CLAUDE_SKILLS_FILE="$SKILLS_COPY" \
  bash "$ADD" someone/skills cool-thing 2>&1)"
rc=$?
assert_eq 1 "$rc" "allowlist 外は終了コード 1"
assert_contains "trusted-skill-owners.txt" "$out" "allowlist の場所を案内する"
assert_contains "skill-vendor.sh add" "$out" "vendor 導線を案内する"
assert_eq "" "$(cat "$SKILLS_COPY")" "claude-skills.txt に追記しない"
TOTAL=$((TOTAL + 1))
if grep -q "skill install" "$GH_LOG"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: gh skill install を呼ばない"
else
  PASS=$((PASS + 1))
  echo "  PASS: gh skill install を呼ばない"
fi
echo ""

out="$(env PATH="$BIN:$PATH" \
  TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" \
  CLAUDE_SKILLS_FILE="$SKILLS_COPY" \
  SKILL_AGENTS="claude-code" \
  bash "$ADD" anthropics/skills skill-creator 2>&1)"
rc=$?
assert_eq 0 "$rc" "allowlist 内は終了コード 0"
assert_contains "skill install anthropics/skills" "$(cat "$GH_LOG")" "gh を呼ぶ"
assert_contains "anthropics/skills skill-creator" "$(cat "$SKILLS_COPY")" "claude-skills.txt に追記する"
echo ""

echo "=== setup-claude-skills.sh のゲート ==="
: >"$GH_LOG"
SETUP_LIST="$TMP/setup-skills.txt"
cat >"$SETUP_LIST" <<'TXT'
anthropics/skills skill-creator
someone/skills cool-thing
TXT

out="$(env PATH="$BIN:$PATH" \
  TRUSTED_SKILL_OWNERS_FILE="$CUSTOM" \
  CLAUDE_SKILLS_FILE="$SETUP_LIST" \
  SKILL_AGENTS="claude-code" \
  HOME="$TMP/home" \
  bash "$SETUP" 2>&1)"
rc=$?
assert_eq 1 "$rc" "allowlist 外の行があれば終了コード 1"
assert_contains "someone" "$out" "どの owner が拒否されたかを出す"
assert_contains "skill install anthropics/skills" "$(cat "$GH_LOG")" "allowlist 内の行は処理する"
TOTAL=$((TOTAL + 1))
if grep -q "someone/skills" "$GH_LOG"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: allowlist 外は gh を呼ばない"
else
  PASS=$((PASS + 1))
  echo "  PASS: allowlist 外は gh を呼ばない"
fi
echo ""

echo "=== local: 行は廃止されている ==="
TOTAL=$((TOTAL + 1))
if grep -q '^local:' "$SCRIPTS_DIR/claude-skills.txt"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: claude-skills.txt に local: 行が残っている"
else
  PASS=$((PASS + 1))
  echo "  PASS: claude-skills.txt に local: 行が無い"
fi
echo ""

echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "テスト失敗"
  exit 1
fi
echo "全テスト成功"
exit 0
