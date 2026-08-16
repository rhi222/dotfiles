#!/bin/bash
# private-bundle.sh のユニットテスト。
# 偽の $HOME と偽のリポジトリを mktemp -d に作り、実環境には一切触らない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE="$SCRIPT_DIR/private-bundle.sh"

if [[ ! -f "$BUNDLE" ]]; then
  echo "ERROR: $BUNDLE が存在しません"
  exit 1
fi

pass=0
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    fail=$((fail + 1))
  fi
}

ORIG_HOME="$HOME"
FIX=""

run() { bash "$BUNDLE" "$@"; }

# 偽の環境を作る。ADOPT_ENTRIES に並ぶ実パスのうち、テストに必要な分だけを用意する。
# passwords/ は README.md を追跡させ、中身だけが ignore される本番と同じ形にする。
setup() {
  FIX=$(mktemp -d)
  export HOME="$FIX/home"
  export DOTFILES_DIR="$FIX/repo"
  export DOTFILES_PRIVATE_DIR="$FIX/private"

  mkdir -p "$HOME/.claude" "$HOME/.config/linear" "$HOME/.config/dotfiles"
  echo ctx >"$HOME/.claude/local-context.md"
  echo key >"$HOME/.config/linear/api-key"
  echo pat >"$HOME/.config/dotfiles/secret-patterns.txt"

  mkdir -p "$DOTFILES_DIR/.config/git"
  mkdir -p "$DOTFILES_DIR/.config/fish/my/conf.d"
  mkdir -p "$DOTFILES_DIR/.config/AutoHotkey/ahk-snippets/passwords/booking"
  echo local >"$DOTFILES_DIR/.config/git/config-local"
  echo fish >"$DOTFILES_DIR/.config/fish/my/conf.d/99-local.fish"
  : >"$DOTFILES_DIR/.config/AutoHotkey/ahk-snippets/passwords/README.md"
  echo aws >"$DOTFILES_DIR/.config/AutoHotkey/ahk-snippets/passwords/booking/aws.md"

  cat >"$DOTFILES_DIR/.gitignore" <<'IGNORE'
.config/git/config-local
.config/fish/my/conf.d/99-local.fish
.config/AutoHotkey/ahk-snippets/passwords/*
!.config/AutoHotkey/ahk-snippets/passwords/README.md
IGNORE

  git -C "$DOTFILES_DIR" init -q >/dev/null 2>&1
  git -C "$DOTFILES_DIR" add .gitignore \
    .config/AutoHotkey/ahk-snippets/passwords/README.md >/dev/null 2>&1
}

teardown() {
  [ -n "$FIX" ] && rm -rf "$FIX"
  export HOME="$ORIG_HOME"
}

# --- adopt: 既定は dry-run ---
setup
out=$(run adopt 2>&1)
check "dry-run では実体を動かさない" test -f "$DOTFILES_DIR/.config/git/config-local"
check "dry-run では集約先を作らない" test ! -d "$DOTFILES_PRIVATE_DIR"
check "dry-run と分かる出力を出す" grep -q "DRY-RUN" <<<"$out"
teardown

# --- adopt --execute ---
setup
run adopt --execute >/dev/null 2>&1
check "ホーム側を集約先へ移す" test -f "$DOTFILES_PRIVATE_DIR/home/.claude/local-context.md"
check "リポジトリ側を集約先へ移す" test -f "$DOTFILES_PRIVATE_DIR/repo/.config/git/config-local"
check "元の位置は symlink になる" test -L "$DOTFILES_DIR/.config/git/config-local"
check "symlink 経由で中身が読める" grep -q local "$DOTFILES_DIR/.config/git/config-local"
check "ホーム側も symlink になる" test -L "$HOME/.claude/local-context.md"

# @under: 追跡ファイルは残し、ignore された子だけを拾う
check "ignore された子を集約先へ移す" \
  test -f "$DOTFILES_PRIVATE_DIR/repo/.config/AutoHotkey/ahk-snippets/passwords/booking/aws.md"
check "ignore された子は symlink になる" \
  test -L "$DOTFILES_DIR/.config/AutoHotkey/ahk-snippets/passwords/booking"
check "追跡ファイルは動かさない" \
  test -f "$DOTFILES_DIR/.config/AutoHotkey/ahk-snippets/passwords/README.md"
check "追跡ファイルは集約先に入らない" \
  test ! -e "$DOTFILES_PRIVATE_DIR/repo/.config/AutoHotkey/ahk-snippets/passwords/README.md"

# 冪等性: 2回目で壊れない
run adopt --execute >/dev/null 2>&1
check "2回目でも symlink のまま" test -L "$DOTFILES_DIR/.config/git/config-local"
check "2回目でも中身が残る" grep -q local "$DOTFILES_DIR/.config/git/config-local"
teardown

# --- 存在しないエントリ ---
setup
rm "$DOTFILES_DIR/.config/git/config-local"
out=$(run adopt --execute 2>&1)
check "存在しないエントリで失敗しない" test $? -eq 0
check "存在しないエントリを報告する" grep -q "MISS" <<<"$out"
teardown

# --- export / import ---
# 対話プロンプトを避けるためテストでは PRIVATE_BUNDLE_ZIP_PASSWORD を使う
# （zip -e の代わりに -P。平文が ps に乗るので実運用では使わない）
export PRIVATE_BUNDLE_ZIP_PASSWORD=test-pass

setup
run adopt --execute >/dev/null 2>&1

# 集約先の中の相対 symlink。実体を2つ持たないための作りなので、
# zip -y で symlink のまま保存されなければならない
mkdir -p "$DOTFILES_PRIVATE_DIR/repo/.config/skills/inv" \
  "$DOTFILES_PRIVATE_DIR/repo/.config/skills/auto"
echo yml >"$DOTFILES_PRIVATE_DIR/repo/.config/skills/inv/repos.yml"
ln -sn ../inv/repos.yml "$DOTFILES_PRIVATE_DIR/repo/.config/skills/auto/repos.yml"

zipfile="$FIX/bundle.zip"
run export --out "$zipfile" >/dev/null 2>&1
check "zip が作られる" test -f "$zipfile"
check "zip のパーミッションが 600" test "$(stat -c %a "$zipfile")" = 600

# 別の集約先へ展開して往復を確認する
export DOTFILES_PRIVATE_DIR="$FIX/restored"
run import "$zipfile" >/dev/null 2>&1
check "import で集約先が作られる" test -d "$DOTFILES_PRIVATE_DIR"
check "ホーム側の中身が復元される" \
  grep -q ctx "$DOTFILES_PRIVATE_DIR/home/.claude/local-context.md"
check "リポジトリ側の中身が復元される" \
  grep -q local "$DOTFILES_PRIVATE_DIR/repo/.config/git/config-local"
check "symlink は symlink のまま復元される" \
  test -L "$DOTFILES_PRIVATE_DIR/repo/.config/skills/auto/repos.yml"
check "復元した symlink が辿れる" \
  grep -q yml "$DOTFILES_PRIVATE_DIR/repo/.config/skills/auto/repos.yml"
check "ファイルは 600 になる" \
  test "$(stat -c %a "$DOTFILES_PRIVATE_DIR/home/.config/linear/api-key")" = 600
check "ディレクトリは 700 になる" \
  test "$(stat -c %a "$DOTFILES_PRIVATE_DIR/home/.claude")" = 700

# 既存の集約先は既定で上書きしない
out=$(run import "$zipfile" 2>&1)
check "集約先があれば既定で拒否する" test $? -ne 0
check "--force の案内を出す" grep -q -- "--force" <<<"$out"
run import "$zipfile" --force >/dev/null 2>&1
check "--force なら上書きする" test $? -eq 0
teardown

# 集約先が無ければ export は失敗する
setup
rm -rf "$DOTFILES_PRIVATE_DIR"
out=$(run export --out "$FIX/none.zip" 2>&1)
check "集約先が無ければ export は失敗する" test $? -ne 0
check "zip は作られない" test ! -f "$FIX/none.zip"
teardown

unset PRIVATE_BUNDLE_ZIP_PASSWORD

# --- status ---
# status は「見出し (件数)」に続けて項目を字下げで並べ、空行で区切る。
# どのセクションに入ったかを検証したいので、見出しで切り出す。
section() {
  local label="$1" text="$2"
  awk -v lbl="$label" '
    index($0, lbl) == 1 { inside = 1; next }
    /^$/ { inside = 0 }
    inside { print }
  ' <<<"$text"
}

setup
run adopt --execute >/dev/null 2>&1
out=$(run status 2>&1)

check "集約先のパスを出す" grep -q "$DOTFILES_PRIVATE_DIR" <<<"$out"
check "リンク済みに config-local が入る" \
  grep -q "config-local" <<<"$(section "リンク済み" "$out")"
check "リンク済みに api-key が入る" \
  grep -q "api-key" <<<"$(section "リンク済み" "$out")"
# config-work はフィクスチャに作っていないので集約先に無いへ落ちる
check "未作成のエントリは集約先に無いへ入る" \
  grep -q "config-work" <<<"$(section "集約先に無い" "$out")"
check "未リンクは空" test -z "$(section "未リンク" "$out")"
check "リンク切れは空" test -z "$(section "リンク切れ" "$out")"

# 未リンク: 集約先に実体はあるが、リンク先が symlink でない
rm "$DOTFILES_DIR/.config/git/config-local"
out=$(run status 2>&1)
check "未リンクを検出する" grep -q "config-local" <<<"$(section "未リンク" "$out")"
check "未リンクはリンク済みに入らない" \
  bash -c '! grep -q "config-local$" <<<"$(section "リンク済み" "'"$out"'")"'

# リンク切れ: symlink はあるが集約先から実体が消えている
ln -sn "$DOTFILES_PRIVATE_DIR/repo/.config/git/config-local" \
  "$DOTFILES_DIR/.config/git/config-local"
rm "$DOTFILES_PRIVATE_DIR/repo/.config/git/config-local"
out=$(run status 2>&1)
check "リンク切れを検出する" grep -q "config-local" <<<"$(section "リンク切れ" "$out")"
teardown

# 集約先そのものが無い場合は import を案内する
setup
rm -rf "$DOTFILES_PRIVATE_DIR"
out=$(run status 2>&1)
check "集約先が無ければ成功する" test $? -eq 0
check "集約先が無ければ import を案内する" grep -q "import" <<<"$out"
teardown

# --- .gitignore の回帰テスト（本物のリポジトリを read-only で検査する） ---
# adopt すると repo 側は symlink になる。末尾 / のパターンはディレクトリ限定なので
# symlink にマッチせず ignore から外れ、未追跡ファイルとして現れる。
# 実際に js/ と cross-repo-auto-discover/ で起きた。
#
# 「現在 ignore されているか」だけだと fresh clone（まだ実ディレクトリ）では
# 素通りしてしまうので、パターンが末尾 / になっていないことも直接見る。
REAL_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

mapfile -t real_entries < <(
  # shellcheck source=/dev/null  # 宣言（ADOPT_ENTRIES）だけを取り出す
  source "$BUNDLE"
  printf '%s\n' "${ADOPT_ENTRIES[@]}"
)

check "ADOPT_ENTRIES を読み出せる" test "${#real_entries[@]}" -gt 0

for entry in "${real_entries[@]}"; do
  kind="${entry%%:*}"
  rel="${entry#*:}"
  case "$kind" in
    repo)
      check "ignore される: $rel" git -C "$REAL_REPO" check-ignore -q "$rel"
      # 末尾 / のパターンだとディレクトリ限定になり、symlink 化で外れる
      check "ディレクトリ限定パターンでない: $rel" \
        bash -c '! grep -qxF "'"$rel"'/" "'"$REAL_REPO"'/.gitignore"'
      ;;
    repo@under)
      # 親は追跡ファイルを持つので ignore されない。直下の任意の子が ignore されること
      check "直下の子が ignore される: $rel/*" \
        git -C "$REAL_REPO" check-ignore -q "$rel/__probe__"
      ;;
  esac
done

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
