#!/bin/bash
# tunnel.sh の app / env が接続先表から補完されることを固定する。
#
# **`bash <path>/tunnel.sh` と直接実行の両方を見る。** 補完定義は conf.d に置いて
# `complete -c bash` と `complete -c tunnel.sh` を両方登録しているので、
# 片方だけ効く状態に退行しても気づけるようにする。
#
# 接続先表は SSH_TUNNEL_CONFIG で架空値の一時ファイルに差し替える。
# 実 $HOME の表を読むと、端末ごとの中身でテスト結果が変わる。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPLETION_FILE="$REPO_ROOT/.config/fish/my/conf.d/16-tunnel-completion.fish"

if ! command -v fish >/dev/null 2>&1; then
  echo "ERROR: fish が見つかりません"
  exit 1
fi

pass=0
fail=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $desc"
    pass=$((pass + 1))
  else
    echo "NG: $desc"
    echo "      expected: $expected"
    echo "      actual  : $actual"
    fail=$((fail + 1))
  fi
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

CONF="$TEST_DIR/ssh-tunnel.tsv"
cat >"$CONF" <<'EOF'
# コメント行と空行は候補に混ぜない

myapp  stg   user@bastion-stg.example.com   54321  db-stg.example.com   db-stg-ro.example.com
myapp  prod  user@bastion-prod.example.com  64321  db-prod.example.com
other  dev   user@bastion-dev.example.com   54321  db-dev.example.com
EOF

# **--no-config で起動する。** 利用者の conf.d を読むと、他の補完定義の影響を受ける。
complete_for() {
  fish --no-config -c "
    set -gx SSH_TUNNEL_CONFIG '$CONF'
    source '$COMPLETION_FILE'
    complete -C '$1'"
}

check "補完定義がある" "yes" "$([[ -f "$COMPLETION_FILE" ]] && echo yes || echo no)"

# app 位置
expected_apps=$(printf '%s\n' myapp other)
check "bash 経由で app を補完する" "$expected_apps" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh ' | cut -f1 | sort)"
# **~ を展開させない。** 補完に渡すのは「利用者が打った通りの文字列」で、
# fish もその形のまま basename を見る。展開すると検査したい形と別物になる。
# shellcheck disable=SC2088
check "直接実行でも app を補完する" "$expected_apps" \
  "$(complete_for '~/scripts/db/tunnel.sh ' | cut -f1 | sort)"

# env 位置。直前の app に属するものだけを出す。
check "app に属する env だけを補完する" "$(printf '%s\n' prod stg)" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh myapp ' | cut -f1 | sort)"
check "別の app では別の env を補完する" "dev" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh other ' | cut -f1)"

# **env には転送先を説明として付ける。** prod/stg の取り違えが一番痛いので、
# どのポートがどこへ向くかを候補の時点で見せる。
check "env に転送先の説明を付ける" "localhost:64321 -> db-prod.example.com" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh myapp ' | grep '^prod' | cut -f2)"

# オプション位置
check "app env の後に --read-only を補完する" "--read-only" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh myapp stg ' | cut -f1)"

# **候補にファイル名を混ぜない。** app/env はファイルを取らないので、
# カレントのファイルが並ぶと候補が埋まる。
check "app 位置でファイル候補を出さない" "" \
  "$(complete_for 'bash ~/scripts/db/tunnel.sh ' | grep -v '^myapp\|^other')"

# **bash の通常の補完を壊さない。** 2つ目のトークンが tunnel.sh のときだけ
# 割り込む条件にしてあるので、無関係な bash 行では app 候補を出さない。
check "無関係な bash 行に割り込まない" "" \
  "$(complete_for 'bash /etc/hosts ' | grep -x 'myapp\|other')"

# 表が無い端末でも落ちない
check "接続先表が無くても静かに空を返す" "" \
  "$(fish --no-config -c "
    set -gx SSH_TUNNEL_CONFIG '$TEST_DIR/absent.tsv'
    source '$COMPLETION_FILE'
    complete -C 'tunnel.sh '" 2>&1)"

echo "---"
echo "pass: $pass, fail: $fail"
[[ "$fail" -eq 0 ]]
