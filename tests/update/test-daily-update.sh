#!/bin/bash
# daily-update は未導入ツールを追加せず、個別の失敗を集約して後続処理を続ける。
# source 時を含めて実 HOME や実運用ログを変更せず、その判定と終了コードを検査する。
# -e はセットアップ部（source まで）の失敗を即検知するため。テスト本体では無効化する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
DAILY_UPDATE="$SCRIPTS_DIR/update/daily.sh"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
trap 'rm -rf "$TEST_HOME"' EXIT

if [[ ! -f "$DAILY_UPDATE" ]]; then
  echo "ERROR: $DAILY_UPDATE が存在しません"
  exit 1
fi

# 関数定義のみ読み込む（main ガードにより更新処理は走らない）
# shellcheck source=/dev/null
source "$DAILY_UPDATE"
# テスト本体は失敗 rc の捕捉を伴うため `set -e` を無効化（assert 側で判定する）。
set +e

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"

  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
  fi
}

assert_output_contains() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"

  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: [$expected]"
    echo "    actual:              [$actual]"
  fi
}

# 外部ツール更新の定型3分岐「導入済み→呼ぶ / 未導入→skip して rc=0 /
# 実体の失敗→rc 伝播」を検証する。ツールごとに env の差し替え口が違うため、
# その差分は runner 関数に閉じ、ヘルパは共通の3分岐アサーションだけを担う。
#   $1=表示名
#   $2=runner 関数名。present|absent|fail を受け取り、対象関数を1回だけ呼ぶ
#   $3=呼び出しログのパス。各ケースの直前に空にして、実体の呼び出しを記録させる
#   $4=実体が呼ばれたことを示すマーカー文字列（呼び出しログに現れる実サブコマンド）
assert_tool_triad() {
  local name="$1" runner="$2" log="$3" marker="$4"
  local exit_code output

  # 導入済み: 実体を呼び、成功する
  : >"$log"
  exit_code=0
  output=$("$runner" present 2>&1) || exit_code=$?
  assert_eq 0 "$exit_code" "$name: 導入済みなら成功する"
  assert_output_contains "$marker" "$(cat "$log")" "$name: 実体を呼ぶ"

  # 未導入: 実体を呼ばず、成功扱い（毎日 FAILED 通知が飛ぶのを避ける）
  : >"$log"
  exit_code=0
  output=$("$runner" absent 2>&1) || exit_code=$?
  assert_eq 0 "$exit_code" "$name: 未導入でも成功扱い"
  assert_eq 0 "$(grep -c "$marker" "$log")" "$name: 実体を呼ばない"
  assert_output_contains "skipping" "$output" "$name: スキップの理由を出す"

  # 実体の失敗: rc をそのまま伝播する（run_step 側で FAILED として拾わせる）
  : >"$log"
  exit_code=0
  output=$("$runner" fail 2>&1) || exit_code=$?
  assert_eq 1 "$exit_code" "$name: 実体の失敗は隠さない"
}

echo "=== daily-update.sh テスト ==="
echo ""

echo "[1] mise tool backend migration"

MISE_CONFIG="$REPO_ROOT/.config/mise/config.toml"
MISE_FISH_CONFIG="$REPO_ROOT/.config/fish/my/conf.d/01-mise.fish"
legacy_files=0
for file in .default-node-packages .default-npm-packages .default-python-packages .default-go-packages; do
  [[ -e "$REPO_ROOT/.config/mise/$file" ]] && legacy_files=$((legacy_files + 1))
done
assert_eq 0 "$legacy_files" "default package filesを残さない"
assert_eq 0 \
  "$(grep -Ec 'npm_global_update|pip_global_update' "$DAILY_UPDATE")" \
  "daily-updateはnpm/pipをmiseと別に更新しない"
assert_eq 0 \
  "$(grep -Ec 'MISE_(PYTHON|NODE|GO)_DEFAULT_PACKAGES_FILE' "$MISE_FISH_CONFIG")" \
  "Fish設定はdefault package fileを指定しない"
assert_eq 1 \
  "$(grep -c '^"npm:@openai/codex" = "latest"$' "$MISE_CONFIG")" \
  "Node CLIをnpm backendで宣言する"
assert_eq 1 \
  "$(grep -c '^"pipx:python-lsp-server" = ' "$MISE_CONFIG")" \
  "Python CLIをpipx backendで宣言する"
assert_eq 1 \
  "$(grep -c '^"go:golang.org/x/tools/cmd/goimports" = "latest"$' "$MISE_CONFIG")" \
  "Go CLIをgo backendで宣言する"
assert_eq 1 \
  "$(grep -c 'postinstall = "python -m pip install --upgrade boto3 pynvim requests"' "$MISE_CONFIG")" \
  "Python providerとライブラリをpostinstallで宣言する"

echo ""
echo "[2] worktree cleanup check"

# daily-update.sh の source 時に LOG_FILE は実運用ログ
# (~/.local/state/daily-update/YYYY-MM-DD.log) を指している。
# run_step_soft はそこに追記するため、テスト中は一時ファイルへ差し替える。
WT_TEST_DIR="$(mktemp -d)"
# SC2034: LOG_FILE は source 済みの daily-update.sh 内の run_step_soft / run_step が
# tee -a "$LOG_FILE" で参照する。shellcheck は source 先の関数からの参照を追えず未使用と誤検知する。
# ここで一時ファイルへ差し替えることで、テスト中に実運用ログを汚さない役割がある。
# shellcheck disable=SC2034
LOG_FILE="$WT_TEST_DIR/test.log"

# run_step_soft は失敗しても failures に積まない
failures=()
run_step_soft "always fails" bash -c 'exit 3' >/dev/null 2>&1
assert_eq 0 "${#failures[@]}" "run_step_soft は失敗を failures に積まない"

# run_step は積む（既存挙動が壊れていないことの確認）
failures=()
run_step "always fails" bash -c 'exit 3' >/dev/null 2>&1
assert_eq 1 "${#failures[@]}" "run_step は失敗を failures に積む"

# powershell.exe のスタブ。渡された引数を丸ごとログに書き出す。
# SCRIPT_DIR は実ディレクトリのままなので本物の lib/notify-windows-toast.sh が
# source され、その中の send_windows_toast が powershell.exe を呼ぶ。つまり通知経路
# 全体を本物のコードで通し、最終段の powershell.exe だけをスタブ化して検証する。
STUB_BIN="$(mktemp -d)"
cat >"$STUB_BIN/powershell.exe" <<EOF
#!/bin/bash
echo "TOAST_CALLED args=[\$*]" >>"$WT_TEST_DIR/toast.log"
EOF
chmod +x "$STUB_BIN/powershell.exe"

# 候補3件を返す偽 worktree-cleanup.sh。SCRIPT_DIR は差し替えず、掃除スクリプトの
# 場所だけを WORKTREE_CLEANUP_SCRIPT で偽物に向ける。
FAKE_SCRIPTS="$(mktemp -d)"
FAKE_SCRIPT="$FAKE_SCRIPTS/worktree-cleanup.sh"
cat >"$FAKE_SCRIPT" <<'EOF'
#!/bin/bash
echo "worktree cleanup  mode: DRY-RUN"
echo ""
echo "== サマリ =="
echo "worktree-cleanup: DELETE_CANDIDATES=3 PRUNE=0 SKIP=0 KEEP=0"
EOF

: >"$WT_TEST_DIR/toast.log"
output=$(PATH="$STUB_BIN:$PATH" \
  WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPT" \
  WORKTREE_CLEANUP_NOTIFY_THRESHOLD=5 \
  worktree_cleanup_check 2>&1)
assert_output_contains "候補: 3 件" "$output" "候補件数をログに出す"
assert_output_contains "  worktree cleanup  mode: DRY-RUN" "$output" "cleanup の出力を字下げする"
assert_output_contains "  == サマリ ==" "$output" "cleanup 内部の見出しを字下げする"
assert_eq 0 \
  "$(printf '%s\n' "$output" | grep -c '^== サマリ ==$')" \
  "cleanup 内部の見出しを daily-update の左端に出さない"
assert_eq 0 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "閾値未満では通知しない"

: >"$WT_TEST_DIR/toast.log"
output=$(PATH="$STUB_BIN:$PATH" \
  WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPT" \
  WORKTREE_CLEANUP_NOTIFY_THRESHOLD=3 \
  worktree_cleanup_check 2>&1)
assert_eq 1 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "閾値以上で通知する"
# 通知本文に候補件数が入っていること（利用者が何件あるか通知だけで分かる）。
# 本物の send_windows_toast は powershell.exe に -Command 文字列として本文を渡すため、
# 引数を丸ごと記録すれば本文を検証できる。
assert_output_contains "3 件" "$(cat "$WT_TEST_DIR/toast.log")" "通知本文に候補件数を含む"

# powershell.exe が無い環境（WSL2 以外）では通知をスキップし、それでも成功扱い。
# PATH を coreutils だけに絞って powershell.exe を確実に見つからなくする
# （/nonexistent にすると bash/grep 等も消えて件数抽出が 0 になり、ゲート自体を
# 通らなくなるため、掃除スクリプト実行と件数抽出に必要なコマンドは残す）。
: >"$WT_TEST_DIR/toast.log"
exit_code=0
output=$(PATH="/usr/bin:/bin" \
  WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPT" \
  WORKTREE_CLEANUP_NOTIFY_THRESHOLD=3 \
  worktree_cleanup_check 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "powershell.exe が無くても成功扱い"
assert_eq 0 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "powershell.exe が無ければ通知しない"

# 掃除スクリプトが無い環境ではスキップして成功扱い
exit_code=0
output=$(WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPTS/does-not-exist.sh" \
  worktree_cleanup_check 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "worktree-cleanup.sh が無くても成功扱い"
assert_output_contains "スキップ" "$output" "スキップの理由を出す"

rm -rf "$WT_TEST_DIR" "$STUB_BIN" "$FAKE_SCRIPTS"

echo ""
echo "[3] yazi_pkg_upgrade"

YAZI_TEST_DIR="$(mktemp -d)"
YAZI_STUB_BIN="$YAZI_TEST_DIR/bin"
mkdir -p "$YAZI_STUB_BIN"
cat >"$YAZI_STUB_BIN/ya" <<EOF
#!/bin/bash
echo "YA_CALLED args=[\$*]" >>"$YAZI_TEST_DIR/ya.log"
exit "\${YA_EXIT:-0}"
EOF
chmod +x "$YAZI_STUB_BIN/ya"
cat >"$YAZI_STUB_BIN/dotctl" <<EOF
#!/bin/bash
echo "DOTCTL_CALLED args=[\$*]" >>"$YAZI_TEST_DIR/dotctl.log"
exit "\${YAZI_UPDATE_EXIT:-0}"
EOF
chmod +x "$YAZI_STUB_BIN/dotctl"
YAZI_ONLY_BIN="$YAZI_TEST_DIR/bin-no-dotctl"
mkdir -p "$YAZI_ONLY_BIN"
cp "$YAZI_STUB_BIN/ya" "$YAZI_ONLY_BIN/ya"
touch "$YAZI_TEST_DIR/package.toml"

# present=宣言あり / absent=package.toml 無し（yazi 未導入相当）/
# fail=dotctl yazi-update が失敗
run_yazi_case() { # present|absent|fail
  local toml="$YAZI_TEST_DIR/package.toml"
  [[ "$1" == absent ]] && toml="$YAZI_TEST_DIR/does-not-exist.toml"
  local update_exit=0
  [[ "$1" == fail ]] && update_exit=1
  PATH="$YAZI_STUB_BIN:$PATH" YAZI_PACKAGE_FILE="$toml" YAZI_UPDATE_EXIT="$update_exit" \
    yazi_pkg_upgrade
}
assert_tool_triad "yazi" run_yazi_case "$YAZI_TEST_DIR/dotctl.log" "yazi-update"

# dotctlがまだ無い端末では従来どおりyaを直接呼び、更新自体を失わない。
: >"$YAZI_TEST_DIR/ya.log"
exit_code=0
output=$(PATH="$YAZI_ONLY_BIN:/usr/bin:/bin" YAZI_PACKAGE_FILE="$YAZI_TEST_DIR/package.toml" \
  yazi_pkg_upgrade 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "dotctlが無ければyaへfallbackして成功する"
assert_output_contains "pkg upgrade" "$(cat "$YAZI_TEST_DIR/ya.log")" "fallbackでyaを呼ぶ"

rm -rf "$YAZI_TEST_DIR"

echo ""
echo "[4] dotctl_rebuild"

# **git pull 後に再ビルドしないと、cron と hook は古いバイナリを黙って実行し
# 続ける**（daily-update.sh が古い installs/<tool>/ の gh を掴んだ事故と同型）。
# 日次で追随させる。
DOTCTL_TEST_DIR="$(mktemp -d)"
DOTCTL_STUB_BIN="$DOTCTL_TEST_DIR/bin"
mkdir -p "$DOTCTL_STUB_BIN"
printf 'module x\n' >"$DOTCTL_TEST_DIR/go.mod"
cat >"$DOTCTL_STUB_BIN/go" <<'GOEOF'
#!/bin/bash
exit 0
GOEOF
chmod +x "$DOTCTL_STUB_BIN/go"
cat >"$DOTCTL_TEST_DIR/setup-dotctl.sh" <<EOF
#!/bin/bash
echo "SETUP_CALLED args=[\$*]" >>"$DOTCTL_TEST_DIR/setup.log"
exit "\${SETUP_EXIT:-0}"
EOF
chmod +x "$DOTCTL_TEST_DIR/setup-dotctl.sh"

# present=go あり / absent=go 無し（未導入相当。yazi の package.toml と同じ扱いで
# 毎日 FAILED 通知が飛ぶのを避ける）/ fail=ビルド失敗（run_step で FAILED として拾う）
#
# **absent を PATH を削って作らない。** CI の runner は /usr/bin:/bin にも go を
# 持っており、それで CI だけ落ちた。go の在処を指す変数側で不在を作る。
run_dotctl_case() { # present|absent|fail
  local go_bin=go
  [[ "$1" == absent ]] && go_bin=definitely-not-go
  local setup_exit=0
  [[ "$1" == fail ]] && setup_exit=1
  PATH="$DOTCTL_STUB_BIN:$PATH" \
    DOTCTL_GO_BIN="$go_bin" \
    DOTCTL_GO_MOD="$DOTCTL_TEST_DIR/go.mod" \
    DOTCTL_SETUP_SCRIPT="$DOTCTL_TEST_DIR/setup-dotctl.sh" \
    SETUP_EXIT="$setup_exit" \
    dotctl_rebuild
}
assert_tool_triad "dotctl" run_dotctl_case "$DOTCTL_TEST_DIR/setup.log" "SETUP_CALLED"

# go.mod が無いリポジトリでも呼ばずに成功扱い（triad の絞りとは別軸の固有分岐）
: >"$DOTCTL_TEST_DIR/setup.log"
exit_code=0
output=$(PATH="$DOTCTL_STUB_BIN:$PATH" \
  DOTCTL_GO_MOD="$DOTCTL_TEST_DIR/nope.mod" \
  DOTCTL_SETUP_SCRIPT="$DOTCTL_TEST_DIR/setup-dotctl.sh" \
  dotctl_rebuild 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "go.mod が無くても成功扱い"
assert_eq 0 "$(grep -c SETUP_CALLED "$DOTCTL_TEST_DIR/setup.log")" "setup-dotctl.sh を呼ばない"

rm -rf "$DOTCTL_TEST_DIR"

echo ""
echo "[5] fisher_update"

FISHER_TEST_DIR="$(mktemp -d)"
FISHER_STUB_BIN="$FISHER_TEST_DIR/bin"
mkdir -p "$FISHER_STUB_BIN"
cat >"$FISHER_STUB_BIN/fish" <<EOF
#!/bin/bash
echo "FISH_CALLED args=[\$*]" >>"$FISHER_TEST_DIR/fish.log"
exit "\${HAS_FISHER_EXIT:-0}"
EOF
chmod +x "$FISHER_STUB_BIN/fish"
cat >"$FISHER_STUB_BIN/dotctl" <<EOF
#!/bin/bash
echo "DOTCTL_CALLED args=[\$*]" >>"$FISHER_TEST_DIR/dotctl.log"
exit "\${FISHER_EXIT:-0}"
EOF
chmod +x "$FISHER_STUB_BIN/dotctl"

# present=fish と fisher が揃う / absent=fish 無し（未導入相当）/ fail=fisher update が失敗。
# remote/cache判定はGo unit testで固定し、ここはShell入口のtriadだけを見る。
run_fisher_case() { # present|absent|fail
  local path="$FISHER_STUB_BIN:$PATH"
  [[ "$1" == absent ]] && path="/nonexistent"
  local fisher_exit=0
  [[ "$1" == fail ]] && fisher_exit=1
  PATH="$path" FISHER_EXIT="$fisher_exit" fisher_update
}
assert_tool_triad "fisher" run_fisher_case "$FISHER_TEST_DIR/dotctl.log" "fisher-update"

# fish はあるが fisher 未導入。追加は setup-fish-plugins.sh の担当なので
# ここでは入れずに成功扱いにし、案内だけ出す（triad の絞りとは別軸の固有分岐）
: >"$FISHER_TEST_DIR/fish.log"
: >"$FISHER_TEST_DIR/dotctl.log"
exit_code=0
output=$(PATH="$FISHER_STUB_BIN:$PATH" HAS_FISHER_EXIT=1 fisher_update 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "fisher 未導入でも成功扱い"
assert_eq 0 "$(grep -c "fisher-update" "$FISHER_TEST_DIR/dotctl.log")" "勝手に入れない"
assert_output_contains "setup/fish-plugins.sh" "$output" "追加の導線を案内する"

rm -rf "$FISHER_TEST_DIR"

# env-residueは端末移行時に手動実行する診断で、日次更新には含めない。
TOTAL=$((TOTAL + 1))
if grep -qE 'env_residue_check|環境の残骸チェック' "$DAILY_UPDATE"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: env-residueをdaily-updateから実行しない"
else
  PASS=$((PASS + 1))
  echo "  PASS: env-residueをdaily-updateから実行しない"
fi

echo ""
echo "[6] cargo_install_update"

CARGO_TEST_DIR="$(mktemp -d)"
CARGO_STUB_BIN="$CARGO_TEST_DIR/bin"
mkdir -p "$CARGO_STUB_BIN"
cat >"$CARGO_STUB_BIN/cargo" <<EOF
#!/bin/bash
echo "CARGO_CALLED args=[\$*]" >>"$CARGO_TEST_DIR/cargo.log"
exit "\${CARGO_EXIT:-0}"
EOF
chmod +x "$CARGO_STUB_BIN/cargo"
# サブコマンドの提供元。cargo は cargo-<sub> という名前のバイナリを PATH から引く
cat >"$CARGO_STUB_BIN/cargo-install-update" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$CARGO_STUB_BIN/cargo-install-update"

# absent 用に cargo だけあって cargo-install-update が無い PATH を用意する
CARGO_ONLY_BIN="$CARGO_TEST_DIR/bin-nocrate"
mkdir -p "$CARGO_ONLY_BIN"
cp "$CARGO_STUB_BIN/cargo" "$CARGO_ONLY_BIN/cargo"

# present=cargo-update あり / absent=cargo-update 無し（未導入相当。更新対象も手段も
# 無い端末で毎日 FAILED 通知が飛ぶのを避ける）/ fail=cargo が失敗。
# absent は PATH をスタブだけに絞り、実機の ~/.cargo/bin を拾わせない。
run_cargo_case() { # present|absent|fail
  local path="$CARGO_STUB_BIN:$PATH"
  [[ "$1" == absent ]] && path="$CARGO_ONLY_BIN:/usr/bin:/bin"
  local cargo_exit=0
  [[ "$1" == fail ]] && cargo_exit=1
  PATH="$path" CARGO_EXIT="$cargo_exit" cargo_install_update
}
assert_tool_triad "cargo" run_cargo_case "$CARGO_TEST_DIR/cargo.log" "install-update -a"

rm -rf "$CARGO_TEST_DIR"

echo ""
# =============================================================================
echo "=== vendored_skill_check ==="
# vendored skill の更新は検知するだけで、ファイルは触らない。
# 実体は symlink で ~/.claude/skills へ生で繋がるので、作業ツリーを書き換えた
# 瞬間に有効になる。未レビューのコードが有効になる瞬間を作らないため

vsc="$(mktemp -d)"
mkdir -p "$vsc/skills-vendor/one"
# **--initial-branch を明示する。** 省くと bare の HEAD は端末の
# init.defaultBranch 依存になり、master の端末では refs/heads/master を指す。
# vendored_skill_check は `git ls-remote <origin> HEAD` で追随を見るので、
# HEAD が存在しないブランチを指していると常に「upstream を確認できません」に
# 落ちて更新検知の2件が静かに落ちる（CI だけ赤になった）。
git init --bare --quiet --initial-branch=main "$vsc/origin.git"
git init --quiet --initial-branch=main "$vsc/work"
git -C "$vsc/work" config user.email test@example.com
git -C "$vsc/work" config user.name test
echo x >"$vsc/work/f"
git -C "$vsc/work" add -A
git -C "$vsc/work" commit --quiet -m init
git -C "$vsc/work" remote add origin "$vsc/origin.git"
git -C "$vsc/work" push --quiet origin HEAD:refs/heads/main
vsc_head1="$(git -C "$vsc/work" rev-parse HEAD)"

jq -n --arg o "$vsc/origin.git" --arg c "$vsc_head1" \
  '{origin:$o, sub_path:".", commit:$c, vendored_at:"2026-08-19",
    reviewed_commit:$c, audit:{high:0,med:0,low:0}, license:"MIT"}' \
  >"$vsc/skills-vendor/one/.vendor.json"
mkdir -p "$vsc/skills-vendor/two"
cp "$vsc/skills-vendor/one/.vendor.json" "$vsc/skills-vendor/two/.vendor.json"

out="$(SKILL_VENDOR_DIR="$vsc/skills-vendor" vendored_skill_check 2>&1)"
assert_eq 0 "$?" "最新なら終了コードは 0"
TOTAL=$((TOTAL + 1))
if echo "$out" | grep -qF "更新あり"; then
  FAIL=$((FAIL + 1))
  echo "  FAIL: 最新時に更新ありと言わない"
else
  PASS=$((PASS + 1))
  echo "  PASS: 最新時に更新ありと言わない"
fi

# upstream を進める
echo y >>"$vsc/work/f"
git -C "$vsc/work" add -A
git -C "$vsc/work" commit --quiet -m next
git -C "$vsc/work" push --quiet origin HEAD:refs/heads/main

out="$(SKILL_VENDOR_DIR="$vsc/skills-vendor" vendored_skill_check 2>&1)"
assert_eq 0 "$?" "更新があっても終了コードは 0"
assert_output_contains "更新あり" "$out" "更新ありと報告する"
assert_output_contains "一括取込: bash scripts/skills/vendor.sh update one two" "$out" \
  "更新対象の一括取込コマンドを案内する"
assert_output_contains "$vsc_head1" "$(cat "$vsc/skills-vendor/one/.vendor.json")" \
  ".vendor.json は書き換えない"

# 到達できない origin でも落ちない（ネットワーク断・private リポジトリ・新環境）
jq '.origin = "/nonexistent/repo.git"' "$vsc/skills-vendor/one/.vendor.json" >"$vsc/j" &&
  mv "$vsc/j" "$vsc/skills-vendor/one/.vendor.json"
out="$(SKILL_VENDOR_DIR="$vsc/skills-vendor" vendored_skill_check 2>&1)"
assert_eq 0 "$?" "origin に到達できなくても終了コードは 0"
assert_output_contains "確認できません" "$out" "確認できなかったことを報告する"

# .vendor.json が無いディレクトリがあっても落ちない
mkdir -p "$vsc/skills-vendor/broken"
out="$(SKILL_VENDOR_DIR="$vsc/skills-vendor" vendored_skill_check 2>&1)"
assert_eq 0 "$?" ".vendor.json が無くても終了コードは 0"
assert_output_contains ".vendor.json が無い" "$out" "欠落を報告する"

# vendored skill が0件でも落ちない
mkdir -p "$vsc/empty"
out="$(SKILL_VENDOR_DIR="$vsc/empty" vendored_skill_check 2>&1)"
assert_eq 0 "$?" "0件でも終了コードは 0"
assert_output_contains "ありません" "$out" "0件であることを報告する"

# 存在しないディレクトリでも落ちない
out="$(SKILL_VENDOR_DIR="$vsc/no-such-dir" vendored_skill_check 2>&1)"
assert_eq 0 "$?" "ディレクトリ不在でも終了コードは 0"

# main が run_step_soft で呼んでいること。
# ネットワーク断で毎日 FAILED 通知が飛ぶと無視されるようになるため
TOTAL=$((TOTAL + 1))
if grep -qF 'run_step_soft "vendored skill 更新チェック" vendored_skill_check' "$DAILY_UPDATE"; then
  PASS=$((PASS + 1))
  echo "  PASS: run_step_soft で呼んでいる"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: run_step_soft で呼んでいる"
fi

rm -rf "$vsc"
echo ""

echo "=== 結果 ==="
echo "TOTAL: $TOTAL  PASS: $PASS  FAIL: $FAIL"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "テスト失敗"
  exit 1
else
  echo "全テスト成功"
  exit 0
fi
