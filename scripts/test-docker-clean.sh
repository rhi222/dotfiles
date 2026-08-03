#!/bin/bash
# fish関数 dclean / __docker_clean_* のユニットテスト
# docker をフェイクスクリプトに差し替え、固定のフィクスチャを返させて検証する
#
# fishのコードをシングルクォートで埋め込むため、$status や $argv をbashに展開させない。
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FUNC_DIR="$(cd "$SCRIPT_DIR/../.config/fish/my/functions" && pwd)"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq が見つかりません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
BIN=""
CACHE=""
FAKE_LOG=""

assert_eq() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name (expected=$expected, got=$actual)"
  fi
}

assert_contains() {
  local expected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  # -e: `--force` のようにハイフン始まりの文字列を検索できるようにする
  if echo "$actual" | grep -qF -e "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

# 純関数だけを source して式を評価する（docker 不要）
run_pure() {
  fish --no-config -c "
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    $1
  " 2>&1
}

# フェイク docker を作る。
#   - 呼ばれた引数を $FAKE_LOG に追記する（prune が走ったかの検証用）
#   - system df / ps / inspect / images / volume / buildx du は固定フィクスチャを返す
#   - DOCKER_FAKE_DOWN=1 のとき info が非ゼロ終了する（デーモン停止の再現）
make_fake_docker() {
  cat >"$BIN/docker" <<'FAKE'
#!/bin/bash
echo "$*" >>"$DOCKER_FAKE_LOG"

case "$1 $2" in
  "info ")
    [[ -n "${DOCKER_FAKE_DOWN:-}" ]] && {
      echo "Cannot connect to the Docker daemon" >&2
      exit 1
    }
    echo "Server Version: 29.7.1"
    exit 0
    ;;
esac

case "$1" in
  system)
    # system df --format json
    cat <<'JSON'
{"Active":"6","Reclaimable":"12.53GB (51%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}
{"Active":"6","Reclaimable":"2.037MB (48%)","Size":"4.215MB","TotalCount":"7","Type":"Containers"}
{"Active":"3","Reclaimable":"50.28MB (0%)","Size":"9.531GB","TotalCount":"99","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"6.776GB","Size":"13.03GB","TotalCount":"591","Type":"Build Cache"}
JSON
    exit 0
    ;;
  ps)
    if [[ "$*" == *"-a"* ]]; then
      # 停止コンテナ 1 件
      echo "aaaa111"
    else
      # 稼働コンテナ 3 件
      echo "c1"
      echo "c2"
      echo "c3"
    fi
    exit 0
    ;;
  inspect)
    # StartedAt は現在時刻から逆算する（c1=24h前, c2=24h前, c3=1h前）。
    # fish 側は実時刻で稼働秒数を計算するため、固定 epoch を使うとズレる。
    now="${DOCKER_FAKE_NOW:-$(date +%s)}"
    printf '/wbc-booking-record_db_test|wbc-booking-record_docker-test_db|%s\n' \
      "$(date -u -d "@$((now - 86400))" +%Y-%m-%dT%H:%M:%S.000000000Z)"
    printf '/buildx_buildkit_peaceful_curran0|moby/buildkit:buildx-stable-1|%s\n' \
      "$(date -u -d "@$((now - 86400))" +%Y-%m-%dT%H:%M:%S.000000000Z)"
    printf '/suspicious_gagarin|whale-pool.fdev:5000/forcia-remote-mcp/forcia-mcp:latest|%s\n' \
      "$(date -u -d "@$((now - 3600))" +%Y-%m-%dT%H:%M:%S.000000000Z)"
    exit 0
    ;;
  images)
    if [[ "$*" == *"{{.Size}}"* ]]; then
      echo "233MB"
      echo "230MB"
    else
      echo "img1"
      echo "img2"
    fi
    exit 0
    ;;
  volume)
    # dangling volume: 匿名 3 件 + named 1 件。
    # 件数を他の行（停止1件 / image2件 / cache2件）と重複させないため 3 件にする。
    echo "0b65d1f82349db533234782857c7df0bd5ae4845308ba9fa80c90ad2f806a23a"
    echo "1f1f7b706eba25c3056f3ea7615f8aa00bd40ea2a6b147bf5b80c986b7e09d37"
    echo "2ba0e3592d9a8cf60f6cdb5331c5222ffbfed31f7b91ff3afb44cb00cf1191df"
    echo "wbc-booking-record_docker_pgdata"
    exit 0
    ;;
  buildx | builder)
    if [[ "$2" == "du" ]]; then
      echo '{"ID":"a","Reclaimable":true,"Size":"577.8MB*","Type":"regular"}'
      echo '{"ID":"b","Reclaimable":true,"Size":"1.026GB","Type":"regular"}'
      echo '{"ID":"c","Reclaimable":false,"Size":"100MB","Type":"regular"}'
      exit 0
    fi
    echo "Total reclaimed space: 1.6GB"
    exit 0
    ;;
  container | image)
    echo "Total reclaimed space: 2.5GB"
    exit 0
    ;;
esac
exit 0
FAKE
  chmod +x "$BIN/docker"
}

setup() {
  TEST_DIR=$(mktemp -d)
  BIN="$TEST_DIR/bin"
  CACHE="$TEST_DIR/stats.json"
  FAKE_LOG="$TEST_DIR/docker.log"
  mkdir -p "$BIN"
  : >"$FAKE_LOG"
  make_fake_docker
}

teardown() {
  rm -rf "$TEST_DIR"
}

# フェイク docker を PATH の先頭に置き、キャッシュを差し替えて fish 式を評価する
run_fish() {
  PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" fish --no-config -c "
    set -g docker_clean_cache_file '$CACHE'
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    source '$FUNC_DIR/__docker_clean_cache_file.fish'
    source '$FUNC_DIR/__docker_clean_stats.fish'
    $1
  " 2>&1
}

echo "=== docker-clean テスト ==="
echo ""

# --- 1. サイズ文字列 → バイト数 ---
echo "[1] __docker_clean_size_to_bytes"
assert_eq "0" "$(run_pure '__docker_clean_size_to_bytes 0B')" "0B"
assert_eq "4128" "$(run_pure '__docker_clean_size_to_bytes 4.128kB')" "小数付き kB"
assert_eq "577800000" "$(run_pure '__docker_clean_size_to_bytes "577.8MB*"')" "共有マーク付き MB"
assert_eq "12530000000" "$(run_pure '__docker_clean_size_to_bytes "12.53GB (51%)"')" "パーセント注記付き GB"
assert_eq "1200000000000" "$(run_pure '__docker_clean_size_to_bytes 1.2TB')" "TB"
assert_eq "1024" "$(run_pure '__docker_clean_size_to_bytes 1KiB')" "二進単位 KiB"
assert_eq "19306776000" "$(run_pure '__docker_clean_size_to_bytes 12.53GB 6.776GB 776000B')" "複数引数を合算する"
assert_eq "0" "$(run_pure '__docker_clean_size_to_bytes')" "引数なしは0"
assert_contains "解釈できない" "$(run_pure '__docker_clean_size_to_bytes nonsense')" "不正な入力はエラーを出す"
assert_eq "1" "$(run_pure '__docker_clean_size_to_bytes nonsense >/dev/null 2>&1; echo $status')" "不正な入力は非ゼロ終了"
echo ""

# --- 2. バイト数 → 人間可読 ---
echo "[2] __docker_clean_format_bytes"
assert_eq "0B" "$(run_pure '__docker_clean_format_bytes 0')" "0"
assert_eq "0B" "$(run_pure '__docker_clean_format_bytes')" "引数なしは0B"
assert_eq "512B" "$(run_pure '__docker_clean_format_bytes 512')" "B"
assert_eq "50.3MB" "$(run_pure '__docker_clean_format_bytes 50280000')" "MB"
assert_eq "19.3GB" "$(run_pure '__docker_clean_format_bytes 19300000000')" "GB"
assert_eq "1.2TB" "$(run_pure '__docker_clean_format_bytes 1200000000000')" "TB"
echo ""

# --- 3. キャッシュの更新・読み出し・TTL ---
echo "[3] __docker_clean_stats のキャッシュ操作"
setup

assert_eq "1" "$(run_fish '__docker_clean_stats --read >/dev/null 2>&1; echo $status')" "キャッシュ無しの --read は非ゼロ"
assert_eq "0" "$(run_fish '__docker_clean_stats --stale; echo $status')" "キャッシュ無しは stale 扱い"

run_fish '__docker_clean_stats --update' >/dev/null
assert_eq "0" "$(run_fish '__docker_clean_stats --read >/dev/null 2>&1; echo $status')" "--update 後の --read は成功"
assert_eq "" "$(run_fish '__docker_clean_stats --update')" "--update は stdout に何も出さない"
assert_eq "4" "$(jq -r '.df | length' "$CACHE")" "df を4種別ぶん保存する"
assert_eq "12.53GB (51%)" "$(jq -r '.df[] | select(.Type=="Images") | .Reclaimable' "$CACHE")" "Images の Reclaimable を保存する"
assert_eq "3" "$(jq -r '.running | length' "$CACHE")" "稼働コンテナ3件を保存する"
assert_eq "wbc-booking-record_db_test" "$(jq -r '.running[0].name' "$CACHE")" "コンテナ名の先頭スラッシュを外す"
# フェイクがStartedAtを生成した時刻とfishがnowを取る時刻に最大数秒のズレが出るため範囲で見る
assert_eq "true" "$(jq -r '.running[0].uptime_seconds >= 86395 and .running[0].uptime_seconds <= 86410' "$CACHE")" "稼働秒数を算出する"
assert_eq "true" "$(jq -r '.generated_at > 0' "$CACHE")" "取得時刻を記録する"

assert_eq "1" "$(run_fish '__docker_clean_stats --stale; echo $status')" "更新直後は stale でない"
# generated_at を 7 時間前に巻き戻すと TTL(6h) 超になる
jq --argjson t "$(($(date +%s) - 7 * 3600))" '.generated_at = $t' "$CACHE" >"$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
assert_eq "0" "$(run_fish '__docker_clean_stats --stale; echo $status')" "TTL超は stale"
assert_eq "1" "$(run_fish 'set -g docker_clean_cache_ttl_h 24; __docker_clean_stats --stale; echo $status')" "TTLを24hに広げれば stale でない"

# 壊れた JSON は無いものとして扱う
echo 'not json' >"$CACHE"
assert_eq "1" "$(run_fish '__docker_clean_stats --read >/dev/null 2>&1; echo $status')" "壊れたキャッシュの --read は非ゼロ"
assert_eq "0" "$(run_fish '__docker_clean_stats --stale; echo $status')" "壊れたキャッシュは stale 扱い"
run_fish '__docker_clean_stats --update' >/dev/null
assert_eq "0" "$(run_fish '__docker_clean_stats --read >/dev/null 2>&1; echo $status')" "壊れたキャッシュは --update で作り直せる"

# デーモン停止時はキャッシュを書かない
rm -f "$CACHE"
assert_eq "1" "$(PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" DOCKER_FAKE_DOWN=1 fish --no-config -c "
  set -g docker_clean_cache_file '$CACHE'
  source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
  source '$FUNC_DIR/__docker_clean_format_bytes.fish'
  source '$FUNC_DIR/__docker_clean_cache_file.fish'
  source '$FUNC_DIR/__docker_clean_stats.fish'
  __docker_clean_stats --update >/dev/null 2>&1; echo \$status")" "デーモン停止時の --update は非ゼロ"
assert_eq "1" "$([[ -f "$CACHE" ]] && echo 0 || echo 1)" "デーモン停止時はキャッシュを作らない"

# 不明な引数
assert_eq "2" "$(run_fish '__docker_clean_stats --bogus >/dev/null 2>&1; echo $status')" "不明な引数は status 2"

teardown
echo ""

# =============================================================================
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
