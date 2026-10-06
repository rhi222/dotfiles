#!/usr/bin/env bash
# _reveal.html を 1920x1080 の PNG に書き出す（操作UI・ヘルプは隠す）。
# 使い方: export_png.sh <deck>_reveal.html <出力ディレクトリ> [スライド番号 ...]
#   スライド番号を省略すると全スライド。番号は 1 始まり。
set -euo pipefail
src=$(realpath "$1"); out=$2; shift 2
mkdir -p "$out"
B=${CHROME:-$(ls ~/.cache/ms-playwright/chromium_headless_shell-*/*/chrome-headless-shell 2>/dev/null | tail -1)}
[ -x "$B" ] || { echo "headless Chromium が見つからない。CHROME=... で指定する" >&2; exit 1; }
tmp=$(mktemp -d)
sed 's#</head>#<style>.help-badge,.reveal .controls,.reveal .progress,.reveal .slide-number{display:none!important}</style></head>#' "$src" > "$tmp/deck.html"
if [ $# -eq 0 ]; then set -- $(seq 1 "$(grep -c '<section data-title=' "$src")"); fi
for n in "$@"; do
  "$B" --no-sandbox --hide-scrollbars --force-device-scale-factor=1.5 --window-size=1280,720 \
    --virtual-time-budget=3000 --screenshot="$out/slide-$(printf %02d "$n").png" "file://$tmp/deck.html#/$((n-1))" 2>/dev/null
done
rm -rf "$tmp"
echo "$out に $# 枚"
