#!/bin/bash
# daily-update は未導入ツールを追加せず、個別の失敗を集約して後続処理を続ける。
# source 時を含めて実 HOME や実運用ログを変更せず、その判定と終了コードを検査する。
# -e はセットアップ部（source まで）の失敗を即検知するため。テスト本体では無効化する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
DAILY_UPDATE_TARGET="$SCRIPTS_DIR/update/daily.sh"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$HOME/scripts"
DAILY_UPDATE="$HOME/scripts/daily-update.sh"
ln -s "$DAILY_UPDATE_TARGET" "$DAILY_UPDATE"
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
  "$(grep -Ec '^[[:space:]]*run_step "mise prune" mise prune --yes$' "$DAILY_UPDATE")" \
  "mise pruneは非対話実行を明示する"
# aube storeは古い版の中身を自動では捨てないため、日次で期限切れを掃除する
assert_eq 1 \
  "$(grep -Ec '^[[:space:]]*run_step "mise cache prune" mise cache prune$' "$DAILY_UPDATE")" \
  "mise cacheの期限切れを日次で掃除する"
# native版の自動更新は黙って止まることがあるため、日次で明示的に更新する
assert_eq 1 \
  "$(grep -Ec '^[[:space:]]*run_step "claude update" claude update </dev/null$' "$DAILY_UPDATE")" \
  "Claude Codeを非対話で更新する"
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

# 候補0件は日次の正常系なので、空の内訳や実行案内を毎日ログへ残さない。
sed 's/DELETE_CANDIDATES=3/DELETE_CANDIDATES=0/' "$FAKE_SCRIPT" >"$FAKE_SCRIPTS/worktree-cleanup-empty.sh"
output=$(PATH="$STUB_BIN:$PATH" \
  WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPTS/worktree-cleanup-empty.sh" \
  WORKTREE_CLEANUP_NOTIFY_THRESHOLD=5 \
  worktree_cleanup_check 2>&1)
assert_output_contains "候補なし" "$output" "候補0件は短い結果だけを出す"
assert_eq 0 \
  "$(printf '%s\n' "$output" | grep -c '== サマリ ==')" \
  "候補0件では cleanup の詳細を再掲しない"
assert_eq 0 \
  "$(printf '%s\n' "$output" | grep -c '通知閾値')" \
  "候補0件では無関係な通知閾値を出さない"

# cleanup が異常終了した場合は、契約行が0件でも診断出力を隠さない。
cat >"$FAKE_SCRIPTS/worktree-cleanup-failed.sh" <<'EOF'
#!/bin/bash
echo "cleanup diagnostic"
echo "worktree-cleanup: DELETE_CANDIDATES=0 PRUNE=0 SKIP=0 KEEP=0"
exit 1
EOF
output=$(WORKTREE_CLEANUP_SCRIPT="$FAKE_SCRIPTS/worktree-cleanup-failed.sh" \
  worktree_cleanup_check 2>&1)
assert_output_contains "cleanup diagnostic" "$output" "cleanup 異常終了時は診断を残す"

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

echo ""
echo "[2b] node_modules_cleanup_check"

# 検知だけで削除しない。合計サイズが閾値以上のときだけ通知する。
cat >"$FAKE_SCRIPTS/nm-cleanup.sh" <<'EOF'
#!/bin/bash
echo "node_modules cleanup  mode: DRY-RUN"
echo "  [DELETE] 3.0G  2026-01-01  /r/a/node_modules"
echo "node-modules-cleanup: CANDIDATES=2 SIZE_MB=4096"
[ "$*" = "" ] || echo "ARGS=[$*]"
EOF

: >"$WT_TEST_DIR/toast.log"
output=$(PATH="$STUB_BIN:$PATH" \
  NODE_MODULES_CLEANUP_SCRIPT="$FAKE_SCRIPTS/nm-cleanup.sh" \
  NODE_MODULES_NOTIFY_THRESHOLD_MB=8192 \
  node_modules_cleanup_check 2>&1)
assert_output_contains "  [DELETE] 3.0G" "$output" "候補の内訳を字下げして出す"
assert_output_contains "2 件 / 4096 MB" "$output" "件数と合計サイズを出す"
assert_eq 0 "$(printf '%s\n' "$output" | grep -c 'ARGS=')" "--execute を渡さず dry-run で呼ぶ"
assert_eq 0 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "サイズが閾値未満なら通知しない"

: >"$WT_TEST_DIR/toast.log"
output=$(PATH="$STUB_BIN:$PATH" \
  NODE_MODULES_CLEANUP_SCRIPT="$FAKE_SCRIPTS/nm-cleanup.sh" \
  NODE_MODULES_NOTIFY_THRESHOLD_MB=4096 \
  node_modules_cleanup_check 2>&1)
assert_eq 1 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "サイズが閾値以上なら通知する"
assert_output_contains "4096 MB" "$(cat "$WT_TEST_DIR/toast.log")" "通知本文に合計サイズを含む"

sed 's/CANDIDATES=2 SIZE_MB=4096/CANDIDATES=0 SIZE_MB=0/' "$FAKE_SCRIPTS/nm-cleanup.sh" >"$FAKE_SCRIPTS/nm-cleanup-empty.sh"
output=$(NODE_MODULES_CLEANUP_SCRIPT="$FAKE_SCRIPTS/nm-cleanup-empty.sh" \
  node_modules_cleanup_check 2>&1)
assert_output_contains "node_modules掃除: 候補なし" "$output" "候補0件は短い結果だけを出す"
assert_eq 0 "$(printf '%s\n' "$output" | grep -c 'DRY-RUN')" "候補0件では詳細を再掲しない"

exit_code=0
output=$(NODE_MODULES_CLEANUP_SCRIPT="$FAKE_SCRIPTS/does-not-exist.sh" \
  node_modules_cleanup_check 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "nodemodules/cleanup.sh が無くても成功扱い"
assert_output_contains "スキップ" "$output" "スキップの理由を出す"

echo ""
echo "[2c] herdr_agent_check"

# 未報告の agent pane が1件でもあれば通知する。restart まで気づけない失敗のため閾値は持たない。
cat >"$FAKE_SCRIPTS/herdr-agent-check.sh" <<'EOF'
#!/bin/bash
echo "  w1:p2	claude	/repo/b"
echo "herdr-agent-check: UNREPORTED=${FAKE_UNREPORTED:-1}"
EOF

: >"$WT_TEST_DIR/toast.log"
output=$(PATH="$STUB_BIN:$PATH" \
  HERDR_AGENT_CHECK_SCRIPT="$FAKE_SCRIPTS/herdr-agent-check.sh" \
  herdr_agent_check 2>&1)
assert_output_contains "w1:p2" "$output" "未報告の pane をログに出す"
assert_eq 1 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "未報告があれば通知する"
assert_output_contains "1 個" "$(cat "$WT_TEST_DIR/toast.log")" "通知本文に件数を含む"

: >"$WT_TEST_DIR/toast.log"
exit_code=0
output=$(PATH="$STUB_BIN:$PATH" FAKE_UNREPORTED=0 \
  HERDR_AGENT_CHECK_SCRIPT="$FAKE_SCRIPTS/herdr-agent-check.sh" \
  herdr_agent_check 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "0件でも成功扱い"
assert_eq 0 "$(grep -c TOAST_CALLED "$WT_TEST_DIR/toast.log")" "0件なら通知しない"

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
echo ""
echo "[7] mise_upgrade"

# 進捗行（resolving の ✓ 行・進捗バー・download 中の行）はログから落とす。
# WARN・version range 外の案内・更新したものの一覧はそのまま残す。
MISE_TEST_DIR="$(mktemp -d)"
cat >"$MISE_TEST_DIR/mise" <<'MISEEOF'
#!/bin/bash
cat >&2 <<'OUT'
mise by @jdx – resolving 63 tools
mise ✓ rust                                 0ms
mise ████████████████ 63/63 · resolved 63 tools in 3ms
mise ███████░░░░░░░░░ 31/63 · 3.0s
  aqua:example/tool@1.0.0                     resolving · fetching from mise-versions.jdx.dev  3.0s
mise ⇢ node@24.21.0         0ms · already installed
mise WARN  newer uv release 0.12.21 ignored by minimum_release_age (48h)
mise by @jdx – installing 1 tools
  uv@0.12.19                     downloading  3.0s  0.1/19.8 MB · 152 kB/s
  uv@0.12.19                     verifying    24.0s
mise ✓ uv@0.12.19                     24.4s  uv-x86_64-unknown-linux-gnu.tar.gz

Upgraded 1 tools:
  uv 0.12.18 → 0.12.19
mise Newer versions are available but do not match the configured version ranges:
  java 21.0.2 → 27.0.0 (config.toml)
OUT
exit "${MISE_EXIT:-0}"
MISEEOF
chmod +x "$MISE_TEST_DIR/mise"

exit_code=0
output=$(PATH="$MISE_TEST_DIR:$PATH" mise_upgrade 2>&1) || exit_code=$?
assert_eq 0 "$exit_code" "mise: 成功なら rc=0"
for noise in "resolving 63 tools" "mise ✓" "████" "fetching from" "already installed" "installing 1 tools" "downloading" "verifying"; do
  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -qF "$noise"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: mise: 進捗行を出さない ($noise)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: mise: 進捗行を出さない ($noise)"
  fi
done
assert_output_contains "mise WARN  newer uv release" "$output" "mise: WARN は残す"
assert_output_contains "Upgraded 1 tools:" "$output" "mise: 更新一覧の見出しを残す"
assert_output_contains "  uv 0.12.18 → 0.12.19" "$output" "mise: 更新したものを残す"
assert_output_contains "  java 21.0.2 → 27.0.0" "$output" "mise: version range 外の案内を残す"

exit_code=0
output=$(PATH="$MISE_TEST_DIR:$PATH" MISE_EXIT=1 mise_upgrade 2>&1) || exit_code=$?
assert_eq 1 "$exit_code" "mise: 失敗の rc を隠さない"
assert_eq 1 "$(grep -c 'run_step "mise upgrade" mise_upgrade$' "$DAILY_UPDATE")" "mise: main から mise_upgrade を呼ぶ"

rm -rf "$MISE_TEST_DIR"

# =============================================================================
echo "=== vendored skill 更新チェック ==="
# 検知は plugin 側と同じ dotctl の status に任せ、出力書式を揃える。
# status はファイルを触らないので、未レビューのコードが有効になる瞬間を作らない。
# ネットワーク断で毎日 FAILED 通知が飛ぶと無視されるようになるため run_step_soft で呼ぶ。
TOTAL=$((TOTAL + 1))
if grep -qE '^ +run_step_soft "vendored skill 更新チェック" bash ".*/skills/vendor[.]sh" status$' "$DAILY_UPDATE"; then
  PASS=$((PASS + 1))
  echo "  PASS: skills/vendor.sh status を run_step_soft で呼んでいる"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: skills/vendor.sh status を run_step_soft で呼んでいる"
fi
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
