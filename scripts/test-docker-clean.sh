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

assert_matches() {
  local pattern="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qE "$pattern"; then
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected to match: $pattern"
    echo "    actual: $actual"
  fi
}

assert_not_contains() {
  local unexpected="$1" actual="$2" test_name="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$actual" | grep -qF -e "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $unexpected"
    echo "    actual: $actual"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $test_name"
  fi
}

# 純関数だけを source して式を評価する（docker 不要）
run_pure() {
  fish --no-config -c "
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    source '$FUNC_DIR/__docker_clean_container_kind.fish'
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
      # 稼働コンテナ 3 件（DOCKER_FAKE_ORPHAN=1 で orphan を 1 件足す）
      echo "c1"
      echo "c2"
      echo "c3"
      [[ -n "${DOCKER_FAKE_ORPHAN:-}" ]] && echo "c4"
    fi
    exit 0
    ;;
  inspect)
    # StartedAt は現在時刻から逆算する（c1=24h前, c2=24h前, c3=1h前）。
    # fish 側は実時刻で稼働秒数を計算するため、固定 epoch を使うとズレる。
    now="${DOCKER_FAKE_NOW:-$(date +%s)}"
    ts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000000000Z; }
    # compose 管理。working_dir は既定で / を指すので test -d が真になり compose と判定される。
    printf '/example-app_db_test|example-app_docker-test_db|%s|example-app|%s|false\n' \
      "$(ts $((now - 86400)))" "${DOCKER_FAKE_COMPOSE_DIR:-/}"
    # standalone（--rm なし）
    printf '/buildx_buildkit_peaceful_curran0|moby/buildkit:buildx-stable-1|%s|||false\n' \
      "$(ts $((now - 86400)))"
    # standalone（--rm あり → 停止で削除される）
    printf '/suspicious_gagarin|registry.example.com:5000/example-org-remote-mcp/example-org-mcp:latest|%s|||true\n' \
      "$(ts $((now - 3600)))"
    # orphan（compose 管理だが working_dir が消えている）。テストが明示的に有効化する。
    if [[ -n "${DOCKER_FAKE_ORPHAN:-}" ]]; then
      printf '/pms-api-localstack|localstack/localstack:4.4|%s|deadproject|%s|false\n' \
        "$(ts $((now - 86400)))" "${DOCKER_FAKE_ORPHAN_DIR:-/nonexistent-worktree-xyz}"
    fi
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
    echo "example-app_docker_pgdata"
    exit 0
    ;;
  buildx | builder)
    if [[ "$2" == "ls" ]]; then
      # ビルダー2つ。docker-container ドライバと daemon 側の default で別キャッシュを持つ。
      echo '{"Current":true,"Driver":"docker-container","Name":"peaceful_curran"}'
      echo '{"Current":false,"Driver":"docker","Name":"default"}'
      exit 0
    fi
    if [[ "$2" == "du" ]]; then
      # ビルダーごとに異なるレコードを返し、合算されることを検証できるようにする
      if [[ "$*" == *"--builder default"* ]]; then
        echo '{"ID":"d","Reclaimable":true,"Size":"500MB","Type":"regular"}'
      else
        echo '{"ID":"a","Reclaimable":true,"Size":"577.8MB*","Type":"regular"}'
        echo '{"ID":"b","Reclaimable":true,"Size":"1.026GB","Type":"regular"}'
        echo '{"ID":"c","Reclaimable":false,"Size":"100MB","Type":"regular"}'
      fi
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
  PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" \
    DOCKER_FAKE_ORPHAN="${DOCKER_FAKE_ORPHAN:-}" \
    DOCKER_FAKE_COMPOSE_DIR="${DOCKER_FAKE_COMPOSE_DIR:-/}" \
    fish --no-config -c "
    set -g docker_clean_cache_file '$CACHE'
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    source '$FUNC_DIR/__docker_clean_container_kind.fish'
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
assert_eq "0" "$(run_fish '__docker_clean_stats --update; echo $status')" "--update は成功を返す"
assert_eq "0" "$(run_fish '__docker_clean_stats --update; __docker_clean_stats --update; echo $status')" "2回目の --update も成功を返す"
assert_eq "4" "$(jq -r '.df | length' "$CACHE")" "df を4種別ぶん保存する"
assert_eq "12.53GB (51%)" "$(jq -r '.df[] | select(.Type=="Images") | .Reclaimable' "$CACHE")" "Images の Reclaimable を保存する"
assert_eq "3" "$(jq -r '.running | length' "$CACHE")" "稼働コンテナ3件を保存する"
assert_eq "example-app_db_test" "$(jq -r '.running[0].name' "$CACHE")" "コンテナ名の先頭スラッシュを外す"
# フェイクがStartedAtを生成した時刻とfishがnowを取る時刻に最大数秒のズレが出るため範囲で見る
assert_eq "true" "$(jq -r '.running[0].uptime_seconds >= 86395 and .running[0].uptime_seconds <= 86410' "$CACHE")" "稼働秒数を算出する"
assert_eq "true" "$(jq -r '.generated_at > 0' "$CACHE")" "取得時刻を記録する"

# 種別判定に必要な label とフラグを保存する
assert_eq "2" "$(jq -r '.schema' "$CACHE")" "スキーマ版を記録する"
assert_eq "example-app" "$(jq -r '.running[0].compose_project' "$CACHE")" "compose project の label を保存する"
assert_eq "/" "$(jq -r '.running[0].compose_dir' "$CACHE")" "compose working_dir の label を保存する"
assert_eq "false" "$(jq -r '.running[0].auto_remove' "$CACHE")" "AutoRemove を保存する（偽）"
assert_eq "" "$(jq -r '.running[1].compose_project' "$CACHE")" "compose 管理外は project が空"
assert_eq "true" "$(jq -r '.running[2].auto_remove' "$CACHE")" "AutoRemove を保存する（真）"
assert_eq "true" "$(jq -r '.running[2].auto_remove | type == "boolean"' "$CACHE")" "AutoRemove は真偽値で保存する"

assert_eq "1" "$(run_fish '__docker_clean_stats --stale; echo $status')" "更新直後は stale でない"

# 旧スキーマのキャッシュは TTL 内でも stale 扱いにする。
# 種別情報が無いキャッシュを読み続けると orphan 件数を出せないため、
# 起動時の background 更新に乗せて次回から正しくする。
jq 'del(.schema)' "$CACHE" >"$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
assert_eq "0" "$(run_fish '__docker_clean_stats --stale; echo $status')" "schema 無しは stale"
jq '.schema = 1' "$CACHE" >"$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
assert_eq "0" "$(run_fish '__docker_clean_stats --stale; echo $status')" "古い schema は stale"
run_fish '__docker_clean_stats --update' >/dev/null
assert_eq "1" "$(run_fish '__docker_clean_stats --stale; echo $status')" "--update すれば stale でなくなる"
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

# --- 4. 通知判定と除外パターン ---
echo "[4] __docker_clean_stats --notice"
setup

# フィクスチャ: Images の Reclaimable と 3 コンテナの稼働秒数だけを可変にする。
# Images 以外の Reclaimable は合計 152.317MB になるよう小さく固定してある。
# こうしておくと「Images を 1.0GB にすればサイズ閾値 5GB 未満」が成立し、
# サイズ条件と稼働条件を独立に検証できる。
write_cache() {
  local reclaim_images="$1" up1="$2" up2="$3" up3="$4"
  cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [
    {"Active":"6","Reclaimable":"$reclaim_images","Size":"24.48GB","TotalCount":"96","Type":"Images"},
    {"Active":"6","Reclaimable":"2.037MB (48%)","Size":"4.215MB","TotalCount":"7","Type":"Containers"},
    {"Active":"3","Reclaimable":"50.28MB (0%)","Size":"9.531GB","TotalCount":"99","Type":"Local Volumes"},
    {"Active":"0","Reclaimable":"100MB","Size":"13.03GB","TotalCount":"591","Type":"Build Cache"}
  ],
  "running": [
    {"name":"example-app_db_test","image":"example-app_docker-test_db","uptime_seconds":$up1,"compose_project":"","compose_dir":"","auto_remove":false},
    {"name":"buildx_buildkit_peaceful_curran0","image":"moby/buildkit:buildx-stable-1","uptime_seconds":$up2,"compose_project":"","compose_dir":"","auto_remove":false},
    {"name":"suspicious_gagarin","image":"registry.example.com:5000/example-org-remote-mcp/example-org-mcp:latest","uptime_seconds":$up3,"compose_project":"","compose_dir":"","auto_remove":true}
  ]
}
JSON
}

# 種別を明示したキャッシュ。compose_dir に実在しないパスを渡すと orphan になる。
write_cache_kinds() {
  local project="$1" dir="$2"
  cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [{"Active":"6","Reclaimable":"1.0GB (10%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}],
  "running": [
    {"name":"example-app_db_test","image":"example-app_docker-test_db","uptime_seconds":86400,"compose_project":"$project","compose_dir":"$dir","auto_remove":false}
  ]
}
JSON
}

# 4-1. Images に偏った回収可能量は重掃除しか消せないので dclean -a を案内する
#
# df の Images Reclaimable は「参照されていない image」の量で dangling かは問わない。
# 軽掃除の image prune -f は dangling だけを消すため、Images を軽掃除の根拠にすると
# 「dclean しても通知が消えない」状態になる（実際になった）。
write_cache "12.53GB (51%)" 86400 86400 86400
out="$(run_fish '__docker_clean_stats --notice')"
assert_contains "docker:" "$out" "通知に docker: を含む"
# 12.53GB + 2.037MB + 50.28MB + 100MB = 12.682317GB → 12.7GB
assert_contains "12.7GB" "$out" "回収可能量の合計を表示する"
assert_contains "未使用 image 中心" "$out" "Images 由来だと分かるようにする"
assert_matches "→ dclean -a" "$out" "重掃除が必要なら dclean -a を案内する"
assert_contains "12h超稼働 1件" "$out" "除外後の長時間稼働は1件"
assert_eq "0" "$(run_fish '__docker_clean_stats --notice >/dev/null; echo $status')" "通知ありは status 0"

# 4-1b. Images 以外（軽掃除で消える分）が閾値を超えたら dclean を案内する
cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "df": [
    {"Active":"6","Reclaimable":"0B","Size":"24.48GB","TotalCount":"96","Type":"Images"},
    {"Active":"6","Reclaimable":"1.0GB","Size":"4.215MB","TotalCount":"7","Type":"Containers"},
    {"Active":"3","Reclaimable":"1.0GB","Size":"9.531GB","TotalCount":"99","Type":"Local Volumes"},
    {"Active":"0","Reclaimable":"6.776GB","Size":"13.03GB","TotalCount":"591","Type":"Build Cache"}
  ],
  "running": []
}
JSON
out="$(run_fish '__docker_clean_stats --notice')"
assert_contains "8.8GB" "$out" "軽掃除で消える分を合算する"
assert_not_contains "未使用 image 中心" "$out" "Images 由来でなければ注記を出さない"
assert_matches "→ dclean$" "$out" "軽掃除で足りるなら dclean を案内する"

# 4-2. サイズ未満 + 長時間稼働なし → 何も出さない
write_cache "1.0GB (10%)" 3600 3600 3600
out="$(run_fish '__docker_clean_stats --notice')"
assert_eq "" "$out" "閾値未満なら何も出さない"
assert_eq "1" "$(run_fish '__docker_clean_stats --notice >/dev/null 2>&1; echo $status')" "閾値未満は status 1"

# 4-3. サイズ未満だが長時間稼働あり → 稼働だけ通知し、確認コマンドを案内する
write_cache "1.0GB (10%)" 86400 3600 3600
out="$(run_fish '__docker_clean_stats --notice')"
assert_contains "12h超稼働 1件" "$out" "サイズ未満でも稼働があれば通知する"
assert_not_contains "回収可能" "$out" "サイズ未満なら回収可能量は出さない"
assert_matches "→ dclean --status" "$out" "稼働だけなら削除ではなく確認を案内する"

# 4-4. サイズ超えだが長時間稼働なし → サイズだけ通知する
write_cache "12.53GB (51%)" 3600 3600 3600
out="$(run_fish '__docker_clean_stats --notice')"
assert_contains "回収可能" "$out" "サイズ超えなら回収可能量を出す"
assert_not_contains "超稼働" "$out" "長時間稼働なしなら稼働の記述は出さない"

# 4-5. 除外パターンが効いている（buildkit と mcp は数えない）
write_cache "1.0GB (10%)" 3600 86400 86400
out="$(run_fish '__docker_clean_stats --notice')"
assert_eq "" "$out" "除外対象だけが長時間稼働なら通知しない"

# 4-6. 閾値を変数で上書きできる
write_cache "1.0GB (10%)" 3600 3600 3600
out="$(run_fish 'set -g docker_clean_size_threshold_gb 1; __docker_clean_stats --notice')"
assert_contains "回収可能" "$out" "サイズ閾値を下げれば通知する"
write_cache "1.0GB (10%)" 7200 3600 3600
out="$(run_fish 'set -g docker_clean_uptime_threshold_h 1; __docker_clean_stats --notice')"
assert_contains "1h超稼働 1件" "$out" "稼働閾値を下げれば通知する"
write_cache "1.0GB (10%)" 3600 86400 3600
out="$(run_fish 'set -g docker_clean_ignore_patterns "nomatch*"; __docker_clean_stats --notice')"
assert_contains "12h超稼働 1件" "$out" "除外パターンを外せば buildkit も数える"

# 4-7. キャッシュが無い/壊れている → 何も出さない
rm -f "$CACHE"
assert_eq "" "$(run_fish '__docker_clean_stats --notice')" "キャッシュ無しなら何も出さない"
echo 'not json' >"$CACHE"
assert_eq "" "$(run_fish '__docker_clean_stats --notice')" "壊れたキャッシュなら何も出さない"

# 4-8. --long-running は除外後の一覧を返す
write_cache "1.0GB (10%)" 86400 86400 86400
out="$(run_fish '__docker_clean_stats --long-running')"
assert_contains "example-app_db_test" "$out" "長時間稼働の対象を出力する"
assert_not_contains "buildx_buildkit" "$out" "除外対象は出力しない"
assert_not_contains "suspicious_gagarin" "$out" "イメージ名で除外されたものは出力しない"

# 4-9. --long-running --excluded は「閾値超えだが除外された」側を返す
write_cache "1.0GB (10%)" 86400 86400 86400
out="$(run_fish '__docker_clean_stats --long-running --excluded')"
assert_contains "buildx_buildkit_peaceful_curran0" "$out" "--excluded は名前で除外されたものを出す"
assert_contains "suspicious_gagarin" "$out" "--excluded はイメージ名で除外されたものを出す"
assert_not_contains "example-app_db_test" "$out" "--excluded は表示対象を出さない"

# 閾値未満なら除外対象でも数えない
write_cache "1.0GB (10%)" 86400 86400 3600
out="$(run_fish '__docker_clean_stats --long-running --excluded')"
assert_contains "buildx_buildkit_peaceful_curran0" "$out" "閾値超えの除外対象は出す"
assert_not_contains "suspicious_gagarin" "$out" "閾値未満は除外対象でも出さない"

# 除外パターンを外せば --excluded は空になる
write_cache "1.0GB (10%)" 86400 86400 86400
out="$(run_fish 'set -g docker_clean_ignore_patterns "nomatch*"; __docker_clean_stats --long-running --excluded')"
assert_eq "" "$out" "パターン不一致なら --excluded は空"

# 4-10. --long-running は種別判定に必要な列も返す（プレビューが分類に使う）
write_cache_kinds example-app /
out="$(run_fish '__docker_clean_stats --long-running')"
assert_eq "6" "$(run_fish '__docker_clean_stats --long-running | head -1 | string split \t | count')" "--long-running は6列を返す"
assert_contains "example-app" "$out" "compose project を含む"

# 4-11. orphan が1件以上なら通知に件数を併記する
write_cache_kinds deadproject /nonexistent-worktree-xyz
out="$(run_fish 'set -g docker_clean_size_threshold_gb 999; __docker_clean_stats --notice')"
assert_contains "12h超稼働 1件（orphan 1）" "$out" "orphan の件数を併記する"

# 4-12. orphan が0件なら括弧を付けない
write_cache_kinds example-app /
out="$(run_fish 'set -g docker_clean_size_threshold_gb 999; __docker_clean_stats --notice')"
assert_contains "12h超稼働 1件" "$out" "稼働件数は出す"
assert_not_contains "orphan" "$out" "orphan 0件なら括弧を付けない"

# 4-13. standalone は orphan に数えない
write_cache "1.0GB (10%)" 86400 86400 86400
out="$(run_fish 'set -g docker_clean_size_threshold_gb 999; __docker_clean_stats --notice')"
assert_not_contains "orphan" "$out" "compose 管理外は orphan に数えない"

# 4-14. 旧スキーマのキャッシュでは orphan 件数を出さない
#
# 種別の列を持たないキャッシュを読んでいる間に件数を書くと嘘になる。
# 旧キャッシュには compose_project が無いため全件 standalone に落ち、結果として
# 括弧は付かない。--stale が真になるので次回起動の background 更新で解消される。
cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "df": [{"Active":"6","Reclaimable":"1.0GB (10%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}],
  "running": [
    {"name":"example-app_db_test","image":"example-app_docker-test_db","uptime_seconds":86400}
  ]
}
JSON
out="$(run_fish 'set -g docker_clean_size_threshold_gb 999; __docker_clean_stats --notice')"
assert_contains "12h超稼働 1件" "$out" "旧スキーマでも稼働件数は出す"
assert_not_contains "orphan" "$out" "旧スキーマでは orphan 件数を出さない"

teardown
echo ""

# dclean まで source して評価する。stdin は呼び出し側で与える。
run_dclean() {
  PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" \
    DOCKER_FAKE_ORPHAN="${DOCKER_FAKE_ORPHAN:-}" \
    DOCKER_FAKE_COMPOSE_DIR="${DOCKER_FAKE_COMPOSE_DIR:-/}" \
    fish --no-config -c "
    set -g docker_clean_cache_file '$CACHE'
    source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
    source '$FUNC_DIR/__docker_clean_format_bytes.fish'
    source '$FUNC_DIR/__docker_clean_container_kind.fish'
    source '$FUNC_DIR/__docker_clean_cache_file.fish'
    source '$FUNC_DIR/__docker_clean_stats.fish'
    source '$FUNC_DIR/dclean.fish'
    $1
  " 2>&1
}

# --- 5. dclean のプレビューと --status ---
echo "[5] dclean --status / --help"
setup

out="$(run_dclean 'dclean --status')"
assert_contains "掃除プレビュー（軽）" "$out" "軽モードのプレビュー見出しを出す"
assert_contains "停止コンテナ" "$out" "停止コンテナ行がある"
assert_contains "dangling image" "$out" "dangling image 行がある"
assert_contains "未使用 volume" "$out" "未使用 volume 行がある"
assert_contains "named volume は対象外" "$out" "named volume を守る注記がある"
assert_contains "build cache" "$out" "build cache 行がある"
assert_contains "回収見込み" "$out" "合計行がある"
assert_contains "稼働中コンテナ" "$out" "稼働中コンテナの一覧見出しがある"
assert_contains "example-app_db_test" "$out" "長時間稼働のコンテナ名を出す"
assert_contains "（除外 1 件" "$out" "除外件数を注記する"
assert_contains "docker_clean_ignore_patterns" "$out" "除外を制御する変数名を案内する"
assert_contains "[compose]" "$out" "compose 管理のコンテナに compose タグを付ける"
assert_contains "docker compose -p example-app down" "$out" "compose はプロジェクト単位の down を案内する"
assert_contains "up で戻せます" "$out" "compose は up で戻せることを注記する"
assert_matches "^  dclean --refresh$" "$out" "停止後のキャッシュ更新を独立行で案内する"
# 既定の除外パターンで standalone は隠れ、orphan は居ないのでどちらのブロックも出ない
assert_not_contains "docker container stop" "$out" "standalone が居なければ stop 行を出さない"
assert_not_contains "# orphan" "$out" "orphan が居なければ orphan ブロックを出さない"

# フェイク docker は匿名3件 + named1件を返す → 匿名だけ数える
assert_matches "未使用 volume +3 件" "$out" "匿名 volume だけを数える（named は除く）"
assert_matches "停止コンテナ +1 件" "$out" "停止コンテナは1件"
assert_matches "dangling image +2 件" "$out" "dangling image は2件"
# build cache は2ビルダー合算で Reclaimable:true が3件
assert_matches "build cache +3 件" "$out" "build cache は全ビルダーの Reclaimable:true を数える"
assert_contains "全ビルダー合算" "$out" "全ビルダーを合算していることを注記する"
# 軽モードは build cache のサイズを出さない（buildx du の合算と実回収量が桁違いになるため）
assert_contains "うち未使用ぶんのみ削除" "$out" "軽モードは削除範囲が一部であることを注記する"
assert_not_contains "最大2.1GB" "$out" "軽モードは build cache のサイズを約束しない"

# 除外が0件なら注記を出さない
out="$(run_dclean 'set -g docker_clean_ignore_patterns "nomatch*"; dclean --status')"
assert_not_contains "除外" "$out" "除外0件なら注記を出さない"

# 長時間稼働が0件なら停止コマンド例を出さない
out="$(run_dclean 'set -g docker_clean_uptime_threshold_h 100; dclean --status')"
assert_contains "閾値を超えて稼働しているコンテナはありません" "$out" "0件時のメッセージは維持"
assert_not_contains "container stop" "$out" "0件なら停止コマンド例を出さない"

# 5-2. orphan（compose 管理だが working_dir が消えている）
out="$(DOCKER_FAKE_ORPHAN=1 run_dclean 'dclean --status')"
assert_matches "^  \[orphan\] +pms-api-localstack +Up [0-9]" "$out" "orphan タグを括弧の外側でパディングする"
assert_contains "└ working_dir なし: /nonexistent-worktree-xyz" "$out" "消えている working_dir のパスを出す"
assert_contains "working_dir が消えているため up では戻せません" "$out" "orphan は up で戻せないことを注記する"
assert_contains "docker compose -p deadproject down" "$out" "orphan もプロジェクト単位の down を案内する"
# orphan と生存 compose は別ブロックに分ける（戻せるかどうかが違う）
assert_contains "docker compose -p example-app down" "$out" "生存 compose の down も併記する"

# 5-3. standalone（--rm あり → 停止で削除される）
out="$(run_dclean 'set -g docker_clean_ignore_patterns "nomatch*"; set -g docker_clean_uptime_threshold_h 0.5; dclean --status')"
assert_matches "^  \[standalone\] +buildx_buildkit_peaceful_curran0 +Up [0-9]" "$out" "standalone タグを出す"
assert_contains "※--rm: 停止で削除されます" "$out" "--rm のコンテナに警告を出す"
assert_contains "docker container stop buildx_buildkit_peaceful_curran0 suspicious_gagarin" "$out" "standalone は container stop でまとめる"
assert_contains "# standalone（※--rm のコンテナは停止で削除されます）" "$out" "standalone ブロックに --rm の注記を付ける"
# compose 系は down、standalone は stop に振り分ける
assert_contains "docker compose -p example-app down" "$out" "compose は down 側に入る"
assert_not_contains "docker container stop example-app_db_test" "$out" "compose を stop 側に入れない"

# 5-4. --rm の standalone が居なければ警告を出さない
out="$(run_dclean 'set -g docker_clean_ignore_patterns "nomatch*"; dclean --status')"
assert_contains "[standalone]" "$out" "standalone タグは出す"
assert_not_contains "※--rm" "$out" "--rm が無ければ警告を出さない"
assert_contains "docker container stop buildx_buildkit_peaceful_curran0" "$out" "stop コマンドは出す"

# --status は削除コマンドを一切呼ばない
assert_not_contains "prune" "$(cat "$FAKE_LOG")" "--status は prune を呼ばない"

# 重モード
out="$(run_dclean 'dclean --status -a')"
assert_contains "掃除プレビュー（重）" "$out" "重モードのプレビュー見出しを出す"
assert_contains "未使用 image" "$out" "重モードは未使用 image 行になる"
assert_matches "未使用 image +90 件" "$out" "未使用 image は TotalCount - Active"
assert_not_contains "dangling image" "$out" "重モードに dangling image 行は出ない"
assert_contains "12.5GB" "$out" "未使用 image のサイズは df の Reclaimable"
# 重モードは build cache を全部消すのでサイズを出す。577.8MB + 1.026GB + 500MB = 2.1GB
assert_contains "最大2.1GB" "$out" "重モードは build cache のサイズを全ビルダーで合算する"

# --help
out="$(run_dclean 'dclean --help')"
assert_contains "使い方" "$out" "--help は使い方を出す"
assert_not_contains "プレビュー" "$out" "--help はプレビューを出さない"

# 不明な引数
assert_eq "2" "$(run_dclean 'dclean --bogus >/dev/null 2>&1; echo $status')" "不明な引数は status 2"

# デーモン停止時
out="$(PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" DOCKER_FAKE_DOWN=1 fish --no-config -c "
  set -g docker_clean_cache_file '$CACHE'
  source '$FUNC_DIR/__docker_clean_size_to_bytes.fish'
  source '$FUNC_DIR/__docker_clean_format_bytes.fish'
  source '$FUNC_DIR/__docker_clean_cache_file.fish'
  source '$FUNC_DIR/__docker_clean_stats.fish'
  source '$FUNC_DIR/dclean.fish'
  dclean --status" 2>&1)"
assert_contains "Docker が起動していません" "$out" "デーモン停止時はエラーメッセージを出す"

teardown
echo ""

# --- 6. dclean の削除実行 ---
echo "[6] dclean の prune 実行"

# 6-1. 確認プロンプトで n を入れたら何も消さない
setup
# NOTE: read -P のプロンプトは stdin が tty でないと出力されないため、表示は検証できない。
# 代わりに y/yes/Y で実行、それ以外で中止という挙動を検証する。
out="$(printf 'n\n' | run_dclean 'dclean')"
assert_contains "中止しました" "$out" "n なら中止する"
assert_not_contains "prune" "$(cat "$FAKE_LOG")" "n なら prune を呼ばない"
teardown

# 6-2. 空入力（Enter のみ）も中止扱い
setup
out="$(printf '\n' | run_dclean 'dclean')"
assert_contains "中止しました" "$out" "Enter のみなら中止する"
assert_not_contains "prune" "$(cat "$FAKE_LOG")" "Enter のみなら prune を呼ばない"
teardown

# 6-3. y で軽掃除が走る
setup
out="$(printf 'y\n' | run_dclean 'dclean')"
log="$(cat "$FAKE_LOG")"
assert_contains "container prune -f" "$log" "軽: container prune を呼ぶ"
assert_matches "^image prune -f$" "$log" "軽: image prune を -a なしで呼ぶ"
assert_contains "volume prune -f" "$log" "軽: volume prune を呼ぶ"
assert_matches "^builder prune -f --builder peaceful_curran$" "$log" "軽: カレントビルダーを掃除する"
assert_matches "^builder prune -f --builder default$" "$log" "軽: default ビルダーも掃除する"
assert_not_contains "image prune -a" "$log" "軽: image prune に -a を付けない"
assert_not_contains "volume prune -a" "$log" "軽: volume prune に -a を付けない"
assert_not_contains "builder prune -a" "$log" "軽: builder prune に -a を付けない"
# until フィルタは docker/docker-container どちらのドライバでも効かず Total: 0B になるため使わない
assert_not_contains "until=" "$log" "軽: 効かない until フィルタを渡さない"
assert_contains "回収:" "$out" "回収量を表示する"
teardown

# 6-4. -a で重掃除が走る
setup
out="$(printf 'y\n' | run_dclean 'dclean -a')"
log="$(cat "$FAKE_LOG")"
assert_contains "image prune -a -f" "$log" "重: image prune に -a を付ける"
assert_matches "^builder prune -a -f --builder peaceful_curran$" "$log" "重: カレントビルダーを全掃除する"
assert_matches "^builder prune -a -f --builder default$" "$log" "重: default ビルダーも全掃除する"
assert_not_contains "volume prune -a" "$log" "重でも volume prune に -a を付けない"
assert_not_contains "until=" "$log" "重も until フィルタを渡さない"
teardown

# 6-5. yes / Y も受け付ける
setup
printf 'yes\n' | run_dclean 'dclean' >/dev/null
assert_contains "container prune" "$(cat "$FAKE_LOG")" "yes を受け付ける"
teardown
setup
printf 'Y\n' | run_dclean 'dclean' >/dev/null
assert_contains "container prune" "$(cat "$FAKE_LOG")" "大文字 Y を受け付ける"
teardown

# 6-6. 個別コマンドが失敗しても残りを続行する
setup
# image prune だけ失敗させるフェイクに差し替える
cat >"$BIN/docker" <<'FAKE'
#!/bin/bash
echo "$*" >>"$DOCKER_FAKE_LOG"
case "$1 $2" in
  "info ")
    echo ok
    exit 0
    ;;
  "system df")
    echo '{"Active":"6","Reclaimable":"12.53GB (51%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}'
    exit 0
    ;;
  "image prune")
    echo "Error response from daemon: boom" >&2
    exit 1
    ;;
esac
case "$1" in
  ps) exit 0 ;;
  volume) exit 0 ;;
  buildx | builder)
    [[ "$2" == ls ]] && exit 0
    [[ "$2" == du ]] && exit 0
    echo "Total reclaimed space: 1.6GB"
    exit 0
    ;;
  container)
    echo "Total reclaimed space: 2.5GB"
    exit 0
    ;;
esac
exit 0
FAKE
chmod +x "$BIN/docker"
out="$(printf 'y\n' | run_dclean 'dclean')"
log="$(cat "$FAKE_LOG")"
assert_contains "失敗" "$out" "失敗したコマンドを報告する"
assert_contains "volume prune -f" "$log" "失敗後も後続の volume prune を実行する"
assert_contains "builder prune" "$log" "失敗後も後続の builder prune を実行する"
assert_eq "1" "$(printf 'y\n' | run_dclean 'dclean >/dev/null 2>&1; echo $status')" "失敗があれば status 1"
teardown

# 6-7. --refresh はキャッシュ更新だけで prune を呼ばない
setup
out="$(run_dclean 'dclean --refresh')"
assert_eq "" "$out" "--refresh は何も出力しない"
assert_eq "0" "$(run_dclean 'dclean --refresh; echo $status')" "--refresh は成功を返す"
assert_not_contains "prune" "$(cat "$FAKE_LOG")" "--refresh は prune を呼ばない"
assert_eq "0" "$([[ -f "$CACHE" ]] && echo 0 || echo 1)" "--refresh はキャッシュを作る"
teardown
echo ""

# --- 7. 起動時通知フック ---
echo "[7] 13-docker-clean.fish"
CONF="$(cd "$SCRIPT_DIR/../.config/fish/my/conf.d" && pwd)/13-docker-clean.fish"
setup

# フックを source して評価する。関数は fish_function_path から autoload させる。
run_hook() {
  PATH="$BIN:$PATH" DOCKER_FAKE_LOG="$FAKE_LOG" fish --no-config -c "
    set -g docker_clean_cache_file '$CACHE'
    set -g fish_function_path '$FUNC_DIR' \$fish_function_path
    source '$CONF'
    $1
  " 2>&1
}

# 7-1. 非対話シェルでは通知しない
assert_eq "" "$(run_hook '')" "非対話では通知しない"

# 7-2. 対話相当の関数を直接呼べば通知する
cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [
    {"Active":"6","Reclaimable":"12.53GB (51%)","Size":"24.48GB","TotalCount":"96","Type":"Images"},
    {"Active":"0","Reclaimable":"6.776GB","Size":"13.03GB","TotalCount":"591","Type":"Build Cache"}
  ],
  "running": [
    {"name":"example-app_db_test","image":"example-app_docker-test_db","uptime_seconds":86400}
  ]
}
JSON
out="$(run_hook '__docker_clean_greeting')"
assert_contains "docker:" "$out" "閾値超えなら通知する"
# Build Cache の 6.776GB だけで閾値を超えるので、軽掃除で足りる扱いになる
assert_contains "6.8GB" "$out" "軽掃除で消える分を表示する"
assert_matches "→ dclean$" "$out" "軽掃除で足りるなら dclean を案内する"

# 7-3. 閾値未満なら黙る
cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [{"Active":"6","Reclaimable":"1.0GB (10%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}],
  "running": []
}
JSON
assert_eq "" "$(run_hook '__docker_clean_greeting')" "閾値未満なら何も出さない"

# 7-4. キャッシュが新しければ background 更新を投げない
assert_not_contains "system df" "$(cat "$FAKE_LOG")" "キャッシュが新しければ docker を叩かない"

# 7-5. キャッシュが古ければ background 更新を投げる（完了を待つ）
jq --argjson t "$(($(date +%s) - 7 * 3600))" '.generated_at = $t' "$CACHE" >"$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
: >"$FAKE_LOG"
run_hook '__docker_clean_greeting' >/dev/null
# background + disown なので完了を待つ
for _ in 1 2 3 4 5 6 7 8 9 10; do
  grep -q "system df" "$FAKE_LOG" && break
  sleep 0.3
done
assert_contains "system df" "$(cat "$FAKE_LOG")" "キャッシュが古ければ background で更新する"

# 7-6. 通知はキャッシュだけを見る（同期的に docker を叩かない）
cat >"$CACHE" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [{"Active":"6","Reclaimable":"12.53GB (51%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}],
  "running": []
}
JSON
: >"$FAKE_LOG"
run_hook '__docker_clean_greeting' >/dev/null
assert_eq "" "$(cat "$FAKE_LOG")" "新しいキャッシュがあれば docker を一切呼ばない"

# 7-7. 実際の対話シェルで通知が出る（config.fish の読み込み順の回帰テスト）
#
# config.fish が my/conf.d を source する前に fish_function_path へ my/functions を
# 足していないと、conf.d から関数を autoload できず fish_command_not_found が走り、
# 通知は黙って出ないまま起動が 380ms 遅くなる。実際に一度これで壊れた。
# XDG_STATE_HOME は環境変数なので conf.d より前に効き、キャッシュ位置を差し替えられる。
XDG_DIR="$TEST_DIR/xdg"
mkdir -p "$XDG_DIR/docker-clean"
cat >"$XDG_DIR/docker-clean/stats.json" <<JSON
{
  "generated_at": $(date +%s),
  "schema": 2,
  "df": [{"Active":"6","Reclaimable":"12.53GB (51%)","Size":"24.48GB","TotalCount":"96","Type":"Images"}],
  "running": []
}
JSON
out="$(XDG_STATE_HOME="$XDG_DIR" fish -i -c exit 2>&1)"
assert_contains "docker:" "$out" "実際の対話シェルで通知が出る"
assert_not_contains "command not found" "$out" "autoload に失敗していない"

teardown
echo ""

# --- 8. コンテナの種別判定 ---
echo "[8] __docker_clean_container_kind"

MISSING="/nonexistent-worktree-xyz-$$"

assert_eq "standalone" "$(run_pure '__docker_clean_container_kind "" ""')" "compose project が空なら standalone"
assert_eq "standalone" "$(run_pure "__docker_clean_container_kind '' /tmp")" "project が空なら dir を見ずに standalone"
assert_eq "compose" "$(run_pure "__docker_clean_container_kind proj /tmp")" "working_dir が存在すれば compose"
assert_eq "orphan" "$(run_pure "__docker_clean_container_kind proj $MISSING")" "working_dir が消えていれば orphan"

# working_dir label が無いときは orphan に倒さない。
# orphan は削除を伴う `docker compose down` を案内する側なので、
# 孤児だと証明できないものを孤児扱いしてはいけない。
assert_eq "compose" "$(run_pure "__docker_clean_container_kind proj ''")" "working_dir 不明なら compose に倒す"
assert_eq "standalone" "$(run_pure '__docker_clean_container_kind')" "引数なしは standalone"

# working_dir がファイル（ディレクトリではない）なら orphan 扱いにする
TMPF=$(mktemp)
assert_eq "orphan" "$(run_pure "__docker_clean_container_kind proj $TMPF")" "working_dir がディレクトリでなければ orphan"
rm -f "$TMPF"

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
