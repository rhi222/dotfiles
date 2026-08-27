#!/bin/bash
#
# dclean（fish の wrapper）と起動時通知の契約を検査する。
#
# **掃除の振る舞いは Go 側が持つ**（internal/docker の unit test）。サイズの
# パース、`math -s1` と同じ表記、`string pad` と同じ表示幅、Images を軽掃除の
# 根拠にしないこと、volume prune に -a を付けないこと、全ビルダーを対象に
# することはすべてそちら（fish 版との一致も Go テストが実物で検証している）。
#
# ここは fish 側の4点だけを見る。
#   1. **autoload だけで解決できるか**（関数名とファイル名が一致しているか）
#   2. fish の設定変数（閾値・除外グロブ）が環境変数へ移って dotctl に届くか
#   3. dotctl の場所を $HOME/.local/bin 優先で解けるか
#   4. 起動時フックがキャッシュを読むだけで、更新を background に逃がすか
#
# **1 が要点。** 初版は `source dclean.fish` で検査していたため、ヘルパーを
# dclean.fish に同居させても通ってしまい、起動時通知が
# `__dclean_dotctl: command not found` で落ちるのを見逃した。fish の autoload は
# 関数名とファイル名の一致を要求するので、**このテストは source せず
# fish_function_path 経由で呼ぶ。**
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNC_DIR="$REPO_ROOT/.config/fish/my/functions"
CONF="$REPO_ROOT/.config/fish/my/conf.d/13-docker-clean.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "SKIP: fish が無い"
  exit 0
fi
if [[ ! -f "$FUNC_DIR/dclean.fish" ]]; then
  echo "ERROR: $FUNC_DIR/dclean.fish が存在しません"
  exit 1
fi

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
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

# background に逃がした処理の完了待ち。固定 sleep は負荷で足りずに落ちるので
# 上限付きポーリングにする。50×0.1秒=5秒は実待ち（1秒未満）より十分大きく取った
# 上限であって計測値ではない。負荷でも間に合わせ、更新が来なければ諦めて抜ける。
wait_for_log() { # $1=grep パターン $2=ログファイル
  for _ in $(seq 1 50); do
    grep -q -- "$1" "$2" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
FAKE_HOME="$TEST_DIR/home"
mkdir -p "$FAKE_HOME/.local/bin"

# dotctl のスタブ。**受け取った引数と環境変数をそのまま吐く**ので、
# fish 側が何を渡しているかを検査できる
cat >"$FAKE_HOME/.local/bin/dotctl" <<'STUB'
#!/bin/bash
echo "ARGS: $*"
for v in DOCKER_CLEAN_SIZE_THRESHOLD_GB DOCKER_CLEAN_UPTIME_THRESHOLD_H \
  DOCKER_CLEAN_CACHE_TTL_H DOCKER_CLEAN_CACHE_FILE DOCKER_CLEAN_IGNORE_PATTERNS; do
  [ -n "${!v:-}" ] && echo "ENV: $v=${!v//$'\n'/,}"
done
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$FAKE_HOME/.local/bin/dotctl"

# **autoload 経路で呼ぶ。** source すると同居させた関数まで定義されるので、
# autoload できない配置でも通ってしまう。実 $HOME は触らない
run_fish() {
  env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" fish -c "
    set -g fish_function_path $FUNC_DIR \$fish_function_path
    $1
  " 2>&1
}

echo "== autoload で解決できるか =="

# **関数名とファイル名が一致していること。** conf.d（起動時通知）は dclean を
# 呼ばずに __dclean_dotctl / __dclean_env を直接使うので、dclean.fish に
# 同居させると「dclean を先に呼んでいないと未定義」になる
for fn in dclean __dclean_dotctl __dclean_env; do
  check "$fn が独立ファイルにある" "yes" \
    "$([ -f "$FUNC_DIR/$fn.fish" ] && echo yes || echo no)"
  check "$fn の関数名がファイル名と一致する" "yes" \
    "$(grep -q "^function $fn " "$FUNC_DIR/$fn.fish" 2>/dev/null && echo yes || echo no)"
done

# autoload だけで呼べること（source しない）
out=$(run_fish 'type -q __dclean_dotctl; and echo AUTOLOADED')
check "__dclean_dotctl を autoload できる" "yes" "$(has 'AUTOLOADED' "$out")"
out=$(run_fish 'type -q __dclean_env; and echo AUTOLOADED')
check "__dclean_env を autoload できる" "yes" "$(has 'AUTOLOADED' "$out")"

echo "== 引数の転送 =="

out=$(run_fish 'dclean')
check "引数なしは docker clean を呼ぶ" "yes" "$(has 'ARGS: docker clean' "$out")"

out=$(run_fish 'dclean -a')
check "-a を素通しする" "yes" "$(has 'ARGS: docker clean -a' "$out")"

out=$(run_fish 'dclean --status')
check "--status を素通しする" "yes" "$(has 'ARGS: docker clean --status' "$out")"

# **--refresh だけは別のサブコマンドに割り当てる**（起動時通知が background で使う）
out=$(run_fish 'dclean --refresh')
check "--refresh は docker refresh を呼ぶ" "yes" "$(has 'ARGS: docker refresh' "$out")"

out=$(run_fish 'dclean --frobnicate')
check "知らない引数も dotctl 側で弾かせる" "yes" "$(has 'ARGS: docker clean --frobnicate' "$out")"

echo "== fish の設定変数が環境変数へ移るか =="

out=$(run_fish '
  set -g docker_clean_size_threshold_gb 9
  set -g docker_clean_uptime_threshold_h 3
  set -g docker_clean_cache_ttl_h 1
  set -g docker_clean_cache_file /tmp/x/stats.json
  dclean --status')
check "サイズ閾値が届く" "yes" "$(has 'DOCKER_CLEAN_SIZE_THRESHOLD_GB=9' "$out")"
check "稼働時間閾値が届く" "yes" "$(has 'DOCKER_CLEAN_UPTIME_THRESHOLD_H=3' "$out")"
check "TTL が届く" "yes" "$(has 'DOCKER_CLEAN_CACHE_TTL_H=1' "$out")"
check "キャッシュの置き場が届く" "yes" "$(has 'DOCKER_CLEAN_CACHE_FILE=/tmp/x/stats.json' "$out")"

# **除外グロブはリスト。** 改行区切りで渡す（空白区切りにすると将来の値で壊れる）
out=$(run_fish '
  set -g docker_clean_ignore_patterns "buildx_buildkit_*" "ghcr.io/example/*"
  dclean --status')
check "除外グロブが全部届く" "yes" "$(has 'DOCKER_CLEAN_IGNORE_PATTERNS=buildx_buildkit_\*,ghcr.io/example/\*' "$out")"

# 未設定なら環境変数を渡さない（Go 側の既定を使わせる）
out=$(run_fish 'dclean --status')
check "未設定なら閾値を渡さない" "no" "$(has 'DOCKER_CLEAN_SIZE_THRESHOLD_GB' "$out")"
check "未設定なら除外グロブを渡さない" "no" "$(has 'DOCKER_CLEAN_IGNORE_PATTERNS' "$out")"

echo "== 終了コードの転送 =="

rc=$(run_fish 'dclean --status >/dev/null 2>&1; echo $status')
check "成功を転送する" "0" "$rc"
rc=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" STUB_EXIT=1 \
  fish -c "set -g fish_function_path $FUNC_DIR \$fish_function_path; dclean --status >/dev/null 2>&1; echo \$status" 2>&1)
check "失敗を転送する" "1" "$rc"

echo "== dotctl の解決 =="

out=$(run_fish '__dclean_dotctl')
check "\$HOME/.local/bin を優先する" "yes" "$(has "$FAKE_HOME/.local/bin/dotctl" "$out")"

# PATH 上にしか無い場合はそちらへ落ちる
mkdir -p "$TEST_DIR/pathbin"
cp "$FAKE_HOME/.local/bin/dotctl" "$TEST_DIR/pathbin/dotctl"
out=$(env HOME="$TEST_DIR/nohome" PATH="$TEST_DIR/pathbin:/usr/bin:/bin" \
  fish -c "set -g fish_function_path $FUNC_DIR \$fish_function_path; __dclean_dotctl" 2>&1)
check "PATH へフォールバックする" "yes" "$(has "$TEST_DIR/pathbin/dotctl" "$out")"

out=$(env HOME="$TEST_DIR/nohome" PATH="/usr/bin:/bin" \
  fish -c "set -g fish_function_path $FUNC_DIR \$fish_function_path; __dclean_dotctl" 2>&1)
rc=$?
check "どこにも無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" "$(has 'setup/dotctl.sh' "$out")"

echo "== 起動時フック =="

# **キャッシュを読むだけ**で、docker を同期実行しないこと。
# stub は docker notice / refresh のどれを呼ばれたかを記録する。
# **notice と stale を別々に呼ぶと、dotctl の version skew 警告が重複する。**
# 起動時の foreground 呼び出しが notice 1回だけであることを回帰検査する。
cat >"$FAKE_HOME/.local/bin/dotctl" <<STUB
#!/bin/bash
echo "\$*" >>"$TEST_DIR/calls.log"
case "\$2" in
  notice) echo "🗑  docker: 6GB 回収可能  → dclean"; exit "\${STALE_EXIT:-1}" ;;
  *)      exit 0 ;;
esac
STUB
chmod +x "$FAKE_HOME/.local/bin/dotctl"

: >"$TEST_DIR/calls.log"
out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" fish -c "
  set -g fish_function_path $FUNC_DIR \$fish_function_path
  source $CONF
  __docker_clean_greeting" 2>&1)
check "通知行を出す" "yes" "$(has '🗑  docker' "$out")"
check "notice を1回だけ呼ぶ" "1" "$(grep -c '^docker notice$' "$TEST_DIR/calls.log")"
check "stale を別に呼ばない" "no" "$(has 'docker stale' "$(cat "$TEST_DIR/calls.log")")"
# 新しければ更新しない（起動を遅くしない）
check "新しければ refresh しない" "no" "$(has 'docker refresh' "$(cat "$TEST_DIR/calls.log")")"

: >"$TEST_DIR/calls.log"
env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" STALE_EXIT=0 fish -c "
  set -g fish_function_path $FUNC_DIR \$fish_function_path
  source $CONF
  __docker_clean_greeting" >/dev/null 2>&1
# background に逃がすので、ログに refresh が現れるまで上限付きで待つ
wait_for_log 'docker refresh' "$TEST_DIR/calls.log"
check "古ければ refresh する" "yes" "$(has 'docker refresh' "$(cat "$TEST_DIR/calls.log")")"

# **docker が無い端末では何も呼ばない。** docker info が command not found
# ハンドラを起こし、起動のたびに snap の導入案内が出る
: >"$TEST_DIR/calls.log"
env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" fish -c "
  set -g fish_function_path $FUNC_DIR \$fish_function_path
  source $CONF" >/dev/null 2>&1
check "非対話 shell では通知しない" "0" "$(grep -c . "$TEST_DIR/calls.log")"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
