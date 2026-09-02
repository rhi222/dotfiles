#!/bin/bash
# scripts/db/tunnel.sh の設定表引きと ssh 引数の組み立てを検査する。
#
# **ssh は PATH 上の stub へ差し替える。** 実際に踏み台へ繋ぐと CI でも手元でも
# 通らないので、組み立てた引数を記録するだけの偽 ssh を通す。
# 設定表は SSH_TUNNEL_CONFIG で差し替え、実 $HOME の設定を読ませない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNNEL="$REPO_ROOT/scripts/db/tunnel.sh"

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

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 引数を記録するだけの ssh
mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/ssh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$SSH_ARGS_FILE"
STUB
chmod +x "$TEST_DIR/bin/ssh"

CONF="$TEST_DIR/ssh-tunnel.tsv"
cat >"$CONF" <<'TSV'
# コメント行は無視する

myapp  stg   user@bastion-stg.example.com   54321  db-stg.example.com   db-stg-ro.example.com
myapp  prod  user@bastion-prod.example.com  64321  db-prod.example.com
TSV

run() {
  env PATH="$TEST_DIR/bin:$PATH" \
    SSH_TUNNEL_CONFIG="$CONF" \
    SSH_ARGS_FILE="$TEST_DIR/ssh-args" \
    bash "$TUNNEL" "$@" 2>&1
}

# 通常系
run myapp stg >/dev/null
check "stg の ssh 引数" \
  "-f -N -o ExitOnForwardFailure=yes -L *:54321:db-stg.example.com:5432 user@bastion-stg.example.com" \
  "$(cat "$TEST_DIR/ssh-args")"

# read-only は6列目を使う
run myapp stg --read-only >/dev/null
check "read-only は6列目のホストへ繋ぐ" \
  "-f -N -o ExitOnForwardFailure=yes -L *:54321:db-stg-ro.example.com:5432 user@bastion-stg.example.com" \
  "$(cat "$TEST_DIR/ssh-args")"

# 6列目が無い行で read-only を求めたら止める
rm -f "$TEST_DIR/ssh-args"
out=$(run myapp prod --read-only)
check "read-only 用ホストが無ければ非0" "1" "$?"
check "read-only 用ホストが無ければ ssh を呼ばない" "no" \
  "$([[ -f "$TEST_DIR/ssh-args" ]] && echo yes || echo no)"

# 未知の組み合わせ
out=$(run myapp nosuchenv)
check "未知の組み合わせは非0" "2" "$?"
check "未知の組み合わせで一覧を出す" "yes" \
  "$(grep -q 'myapp stg' <<<"$out" && echo yes || echo no)"

# 引数不足
out=$(run myapp)
check "引数不足は非0" "2" "$?"

# 不明なオプション
out=$(run myapp stg --nope)
check "不明なオプションは非0" "2" "$?"

# 設定が無い環境
out=$(env PATH="$TEST_DIR/bin:$PATH" SSH_TUNNEL_CONFIG="$TEST_DIR/absent.tsv" bash "$TUNNEL" myapp stg 2>&1)
check "設定が無ければ非0" "1" "$?"
check "設定が無ければ雛形を案内する" "yes" \
  "$(grep -q 'ssh-tunnel.tsv.example' <<<"$out" && echo yes || echo no)"

# repo 同梱の雛形がそのまま読める形式であること
out=$(env PATH="$TEST_DIR/bin:$PATH" \
  SSH_TUNNEL_CONFIG="$REPO_ROOT/scripts/db/ssh-tunnel.tsv.example" \
  SSH_ARGS_FILE="$TEST_DIR/ssh-args" bash "$TUNNEL" 2>&1)
check "雛形の組み合わせを一覧できる" "yes" \
  "$(grep -q 'myapp prod' <<<"$out" && echo yes || echo no)"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
