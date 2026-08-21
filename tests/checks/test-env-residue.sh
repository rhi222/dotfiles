#!/bin/bash
# env-residue.sh のユニットテスト
#
# 「宣言のどこにも属さないのに環境に居座っているもの」を検知する。今日踏んだ
# 3種類（追跡外の fish_user_key_bindings.fish / 旧 fzf の clone / 宣言に無い
# skill の実ディレクトリ）が対象で、どれも既存のどのチェックにも掛からなかった。
#
# HOME と REPO を差し替えて実行する。ネットワークにも実環境にも触らない。
#
# 検査対象は env-residue.sh が出す「表示文」で、そこに現れる `~/...` は展開され
# ないのが正しい。SC2088（チルダは展開されない）はここでは意図どおりなので、
# ファイル単位で黙らせる（1行 disable は直後の1コマンドにしか効かない）。
# shellcheck disable=SC2088
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/scripts"
TARGET="$SCRIPTS_DIR/env-residue.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
FAKE_HOME=""
REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  FAKE_HOME="$TEST_DIR/home"
  REPO="$TEST_DIR/repo"
  mkdir -p "$FAKE_HOME/.config/fish/functions" \
    "$FAKE_HOME/.claude/skills" \
    "$FAKE_HOME/.codex/skills" \
    "$FAKE_HOME/.agents/skills" \
    "$REPO/scripts" \
    "$REPO/.config/fish/my/functions" \
    "$REPO/.config/claude/skills" \
    "$REPO/.config/claude/skills-vendor"
  # 宣言ファイル（trusted な skill の一覧）
  cat >"$REPO/scripts/claude-skills.txt" <<'TXT'
# comment
anthropics/skills frontend-design
vercel-labs/agent-browser agent-browser
TXT
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# fisher のファイル一覧は universal 変数なので、テストではファイルで差し替える
# （ENV_RESIDUE_FISHER_FILES）。実行時は fish から引く。
run_residue() {
  local files="$TEST_DIR/fisher-files.txt"
  [ -f "$files" ] || : >"$files"
  env HOME="$FAKE_HOME" ENV_RESIDUE_REPO="$REPO" \
    ENV_RESIDUE_FISHER_FILES="$files" bash "$TARGET" 2>&1
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

echo "== きれいな環境 =="

setup
out=$(run_residue)
check "何も無ければ成功する" "0" "$?"
check "きれいだと伝える" "yes" "$(has '残骸は見つかりませんでした' "$out")"
teardown

echo "== 旧 fzf の clone =="

setup
mkdir -p "$FAKE_HOME/.fzf"
out=$(run_residue)
# mise 管理と二重になり、PATH 順で古い版を掴む端末が出る
check "~/.fzf を報告する" "yes" "$(has '~/.fzf' "$out")"
# 情報提供なので、見つかっても成功で返す（daily-update を FAILED にしない）
check "見つかっても成功で返す" "0" "$?"
teardown

setup
: >"$FAKE_HOME/.fzf.bash"
out=$(run_residue)
check "~/.fzf.bash も報告する" "yes" "$(has '.fzf.bash' "$out")"
teardown

echo "== 追跡外の fish 関数 =="

setup
# repo が同名を持っていれば fish_function_path の先頭で影にできているので残骸ではない
printf 'function fish_user_key_bindings\nend\n' >"$REPO/.config/fish/my/functions/fish_user_key_bindings.fish"
printf 'function fish_user_key_bindings\n  fzf --fish | source\nend\n' \
  >"$FAKE_HOME/.config/fish/functions/fish_user_key_bindings.fish"
out=$(run_residue)
check "repo が同名を持つなら報告しない" "no" \
  "$(has 'fish_user_key_bindings' "$out")"
teardown

setup
# repo に同名が無いものは、どの導線にも属さない実ファイル
printf 'function whatever\nend\n' >"$FAKE_HOME/.config/fish/functions/whatever.fish"
out=$(run_residue)
check "repo に無い追跡外の関数を報告する" "yes" "$(has 'whatever.fish' "$out")"
teardown

setup
# fisher が入れたものは残骸ではない。判定は名前の規約ではなく fisher 自身が持つ
# ファイル一覧（universal 変数 _fisher_<plugin>_files）で行う。
# tide の fish_prompt.fish のように `_` で始まらない公開関数があるので、
# 名前だけで切ると誤検知する（実環境で5件出た）
printf 'function fish_prompt\nend\n' >"$FAKE_HOME/.config/fish/functions/fish_prompt.fish"
printf 'function _tide_item_git\nend\n' >"$FAKE_HOME/.config/fish/functions/_tide_item_git.fish"
cat >"$TEST_DIR/fisher-files.txt" <<EOF
$FAKE_HOME/.config/fish/functions/fish_prompt.fish
$FAKE_HOME/.config/fish/functions/_tide_item_git.fish
EOF
out=$(run_residue)
check "fisher が入れた公開関数を報告しない" "no" "$(has 'fish_prompt' "$out")"
check "fisher が入れた内部関数も報告しない" "no" "$(has '_tide_item_git' "$out")"
teardown

setup
# fisher の一覧が引けない環境（fish 未導入など）では、名前の規約に落とす。
# `_` 始まりはプラグインの内部関数という広い慣習なので、これだけは除外する
printf 'function _some_plugin_helper\nend\n' >"$FAKE_HOME/.config/fish/functions/_some_plugin_helper.fish"
out=$(env HOME="$FAKE_HOME" ENV_RESIDUE_REPO="$REPO" ENV_RESIDUE_FISHER_FILES=/dev/null \
  bash "$TARGET" 2>&1)
check "一覧が引けなければ _ 始まりを除外する" "no" "$(has '_some_plugin_helper' "$out")"
teardown

setup
# 一覧にも無く `_` でも始まらないものだけが残骸
printf 'function whatever2\nend\n' >"$FAKE_HOME/.config/fish/functions/whatever2.fish"
: >"$TEST_DIR/fisher-files.txt"
out=$(run_residue)
check "一覧に無い公開関数は報告する" "yes" "$(has 'whatever2.fish' "$out")"
teardown

echo "== 宣言に無い skill =="

setup
mkdir -p "$FAKE_HOME/.claude/skills/mystery"
out=$(run_residue)
check "宣言に無い実ディレクトリを報告する" "yes" "$(has 'mystery' "$out")"
check "どのパスかを出す" "yes" "$(has '.claude/skills/mystery' "$out")"
teardown

setup
# trusted（claude-skills.txt にある）は gh が入れた実ディレクトリで正しい姿
mkdir -p "$FAKE_HOME/.claude/skills/frontend-design"
out=$(run_residue)
check "trusted な skill は報告しない" "no" "$(has 'frontend-design' "$out")"
teardown

setup
# 自作 skill は symlink で入る。実ディレクトリでも宣言済みなら残骸ではない
mkdir -p "$REPO/.config/claude/skills/my-own" "$FAKE_HOME/.claude/skills/my-own"
out=$(run_residue)
check "自作 skill は報告しない" "no" "$(has 'my-own' "$out")"
teardown

setup
# vendored は symlink であるべき。実ディレクトリなら古い gh 版が居座っている
mkdir -p "$REPO/.config/claude/skills-vendor/vend" "$FAKE_HOME/.claude/skills/vend"
out=$(run_residue)
check "vendored が実ディレクトリなら報告する" "yes" "$(has 'vend' "$out")"
teardown

setup
mkdir -p "$REPO/.config/claude/skills-vendor/vend"
ln -s "$REPO/.config/claude/skills-vendor/vend" "$FAKE_HOME/.claude/skills/vend"
out=$(run_residue)
check "vendored が symlink なら報告しない" "no" "$(has 'vend' "$out")"
teardown

setup
# codex 側も見る。gh skill install --agent codex はここに入れる
mkdir -p "$FAKE_HOME/.codex/skills/mystery"
out=$(run_residue)
check "codex 側の skills も見る" "yes" "$(has '.codex/skills/mystery' "$out")"
teardown

setup
# codex 同梱の .system は宣言の対象外
mkdir -p "$FAKE_HOME/.codex/skills/.system/imagegen"
out=$(run_residue)
check ".system は報告しない" "no" "$(has '.system' "$out")"
teardown

echo "== 出力の形 =="

setup
mkdir -p "$FAKE_HOME/.fzf" "$FAKE_HOME/.claude/skills/mystery"
out=$(run_residue)
check "複数見つかっても両方出す" "yes" \
  "$([[ "$(has '~/.fzf' "$out")" == yes && "$(has 'mystery' "$out")" == yes ]] && echo yes || echo no)"
# 件数の機械可読サマリ。表示の体裁を変えても呼び出し側が壊れないようにする
check "機械可読サマリ行を出す" "yes" "$(has 'env-residue: FOUND=2' "$out")"
teardown

setup
out=$(run_residue)
check "0件でもサマリ行を出す" "yes" "$(has 'env-residue: FOUND=0' "$out")"
teardown

echo "== 宣言ファイルが無いとき =="

setup
rm -f "$REPO/scripts/claude-skills.txt"
mkdir -p "$FAKE_HOME/.claude/skills/frontend-design"
out=$(run_residue)
# 宣言が読めないまま「宣言に無い」と言うと、正しいものまで残骸に見える
check "skill の宣言が読めなければ skill の判定はしない" "no" "$(has 'frontend-design' "$out")"
check "読めなかったことを伝える" "yes" "$(has 'claude-skills.txt' "$out")"
check "それでも成功で返す" "0" "$?"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
