#!/bin/bash
# daily-update.sh のユニットテスト（純粋関数のみ対象）
# -e はセットアップ部（source まで）の失敗を即検知するため。テスト本体では無効化する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAILY_UPDATE="$SCRIPT_DIR/daily-update.sh"

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

# npm_select_targets <outdated_json> <installed_names> <name...>
# 出力（name@latest の改行区切り）を | 区切りに畳んで比較する
select_targets() {
  npm_select_targets "$@" | paste -sd'|' -
}

# pip_select_targets <outdated_json> <installed_names> <spec...>
select_pip_targets() {
  pip_select_targets "$@" | paste -sd'|' -
}

echo "=== daily-update.sh テスト ==="
echo ""

echo "[1] npm_select_targets"

# 全て最新かつインストール済み → 対象なし
installed=$'prettier\ndifit\naws-cdk'
assert_eq "" \
  "$(select_targets '{}' "$installed" prettier difit aws-cdk)" \
  "全て最新・導入済みなら対象ゼロ"

# outdated に載っているものだけ対象
outdated='{"prettier":{"current":"3.0.0","latest":"3.1.0"}}'
assert_eq "prettier@latest" \
  "$(select_targets "$outdated" "$installed" prettier difit aws-cdk)" \
  "outdated のパッケージのみ対象"

# 未インストール（installed に無い）は outdated に無くても対象
assert_eq "newpkg@latest" \
  "$(select_targets '{}' "$installed" prettier difit newpkg)" \
  "未インストールのパッケージは対象"

# outdated と未インストールの両方
outdated='{"aws-cdk":{"current":"2.0.0","latest":"2.1.0"}}'
assert_eq "aws-cdk@latest|newpkg@latest" \
  "$(select_targets "$outdated" "$installed" prettier aws-cdk newpkg)" \
  "outdated と未インストールを両方拾う"

# 空文字の outdated_json は {} 扱い（npm outdated が何も返さないケース）
assert_eq "" \
  "$(select_targets '' "$installed" prettier difit aws-cdk)" \
  "空の outdated_json は変更なし扱い"

# スコープ付きパッケージ名も正しく判定
installed_scoped=$'@openai/codex\n@github/copilot'
outdated_scoped='{"@openai/codex":{"current":"1.0.0","latest":"1.1.0"}}'
assert_eq "@openai/codex@latest" \
  "$(select_targets "$outdated_scoped" "$installed_scoped" @openai/codex @github/copilot)" \
  "スコープ付き名も outdated 判定できる"

echo ""
echo "[2] pip_select_targets"

pip_installed=$'boto3\nrequests\npython-lsp-server\nsqlfluff'

# 全て最新かつインストール済み → 対象なし
assert_eq "" \
  "$(select_pip_targets '[]' "$pip_installed" boto3 requests)" \
  "全て最新・導入済みなら対象ゼロ"

# outdated の top-level のみ対象
pip_out='[{"name":"sqlfluff","version":"1.0.0","latest_version":"1.1.0"}]'
assert_eq "sqlfluff" \
  "$(select_pip_targets "$pip_out" "$pip_installed" boto3 sqlfluff)" \
  "outdated の top-level のみ対象"

# extras 付き指定はそのまま保持して出力
pip_out='[{"name":"python-lsp-server","version":"1.0","latest_version":"1.1"}]'
assert_eq "python-lsp-server[all]" \
  "$(select_pip_targets "$pip_out" "$pip_installed" 'python-lsp-server[all]')" \
  "extras 付き指定を保持"

# 未インストールは outdated に無くても対象
assert_eq "xmlformatter" \
  "$(select_pip_targets '[]' "$pip_installed" boto3 xmlformatter)" \
  "未インストールは対象"

# 名前正規化: installed が typing_extensions・spec が typing-extensions → 導入済み扱い
assert_eq "" \
  "$(select_pip_targets '[]' 'typing_extensions' typing-extensions)" \
  "アンダースコア/ハイフン差を吸収（導入済み）"

# 名前正規化: outdated が typing_extensions・spec が typing-extensions → 対象
pip_out='[{"name":"typing_extensions","version":"4.15.0","latest_version":"4.16.0"}]'
assert_eq "typing-extensions" \
  "$(select_pip_targets "$pip_out" 'typing_extensions' typing-extensions)" \
  "アンダースコア/ハイフン差を吸収（outdated）"

# 空の outdated_json は [] 扱い
assert_eq "" \
  "$(select_pip_targets '' "$pip_installed" boto3 requests)" \
  "空の outdated_json は変更なし扱い"

echo ""
echo "[3] read_package_list"

# コメント行・空行・行内コメント・空白を除去して1行1エントリで返す
fixture=$(mktemp)
cat >"$fixture" <<'EOF'
# コメント行
prettier

difit  # 行内コメント
  aws-cdk
@openai/codex
EOF
assert_eq $'prettier\ndifit\naws-cdk\n@openai/codex' \
  "$(read_package_list "$fixture")" \
  "コメント・空行・空白を除去して読み込む"

# 空ファイル → 出力なし
: >"$fixture"
assert_eq "" \
  "$(read_package_list "$fixture")" \
  "空ファイルは出力なし"

# コメントのみ → 出力なし
printf '# only comment\n\n' >"$fixture"
assert_eq "" \
  "$(read_package_list "$fixture")" \
  "コメントのみのファイルは出力なし"
rm -f "$fixture"

echo ""
echo "[4] pkg_install_with_diff"

# スタブ: FAKE_STATE ファイルをパッケージ一覧に見立てる。
# pkg_install_with_diff に関数名で渡す間接呼び出しのため SC2329 は誤検知。
FAKE_STATE=$(mktemp)
# shellcheck disable=SC2329
fake_list() { cat "$FAKE_STATE"; }
# shellcheck disable=SC2329
fake_install_ok() { printf 'pkgA\t2.0.0\n' >"$FAKE_STATE"; }
# shellcheck disable=SC2329
fake_install_fail() { return 3; }

# 成功時: diff が報告され、rc=0
printf 'pkgA\t1.0.0\n' >"$FAKE_STATE"
out=$(pkg_install_with_diff fake_list fake_install_ok pkgA)
rc=$?
assert_eq "0" "$rc" "install 成功時は rc=0"
assert_eq $'Upgraded 1 package(s):\n  pkgA 1.0.0 → 2.0.0' \
  "$out" \
  "成功時にアップグレード差分を報告"

# 失敗時: install の rc を伝播しつつ、diff 報告まで実行される（早期終了しない）
printf 'pkgA\t1.0.0\n' >"$FAKE_STATE"
out=$(pkg_install_with_diff fake_list fake_install_fail pkgA)
rc=$?
assert_eq "3" "$rc" "install 失敗時は rc を伝播"
assert_eq "No package changes." \
  "$out" \
  "失敗時も diff 報告まで到達する"
rm -f "$FAKE_STATE"

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
