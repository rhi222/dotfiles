#!/usr/bin/env bash
# tunnel.sh — 設定表を引いて DB への SSH ポートフォワードを張る。
#
#   bash scripts/db/tunnel.sh <app> <env> [--read-only]
#   bash scripts/db/tunnel.sh                              # 組み合わせ一覧
#
# 接続先（社内踏み台・RDS エンドポイント）は repo へ置かない。実体は
# ~/.config/dotfiles/ssh-tunnel.tsv、雛形は隣の ssh-tunnel.tsv.example。
set -euo pipefail

config="${SSH_TUNNEL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ssh-tunnel.tsv}"
example="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh-tunnel.tsv.example"

if [ ! -f "$config" ]; then
  echo "設定がない: $config" >&2
  echo "雛形からコピーする: mkdir -p $(dirname "$config"); cp $example $config" >&2
  exit 1
fi

# コメントと空行を除いた行だけを流す
rows() {
  grep -v '^[[:space:]]*\(#\|$\)' "$config"
}

usage() {
  echo "Usage: $0 <app> <env> [--read-only]" >&2
  echo "[app env の組み合わせ]" >&2
  rows | awk '{print "  " $1 " " $2}' | sort >&2
}

[ "$#" -ge 2 ] || {
  usage
  exit 2
}

app="$1"
env="$2"
shift 2

read_only=false
case "${1:-}" in
  "") ;;
  --read-only) read_only=true ;;
  *)
    echo "不明なオプション: $1" >&2
    usage
    exit 2
    ;;
esac

row=$(rows | awk -v a="$app" -v e="$env" '$1 == a && $2 == e { print; exit }')
[ -n "$row" ] || {
  echo "未知の組み合わせ: $app $env" >&2
  usage
  exit 2
}

read -r _ _ remote port target target_ro <<<"$row"

if $read_only; then
  [ -n "${target_ro:-}" ] || {
    echo "read-only 用のホストが未設定: $app $env" >&2
    exit 1
  }
  target="$target_ro"
  echo "(read-only モード)"
fi

echo ">> localhost:$port -> $target:5432 via $remote"

# ExitOnForwardFailure により、ローカルportの衝突や転送拒否で ssh が非0で落ちる
ssh -f -N -o ExitOnForwardFailure=yes -L "*:$port:$target:5432" "$remote"

echo "Tunnel established."
