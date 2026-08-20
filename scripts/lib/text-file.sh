#!/bin/bash
# テキスト/非テキストの判定。skill-audit.sh と skill-vendor.sh の両方から source する。
#
# 判定は grep -Iq で行う。file --mime はコードブロックの多い .md を
# application/javascript と判定するため使えない（vercel-react-best-practices の
# 正当な rules/*.md 27件が誤って弾かれる）。判定がずれると正当なファイルを黙って
# 落とすので、audit（HIGH で報告）と vendor（取込を拒否）で判定を一致させる。

# ファイルがテキストなら 0。grep -Iq . は行が1つも無いと不一致になるので、
# 空ファイルは「テキストでない」を返す。
is_text_file() {
  grep -Iq . "$1" 2>/dev/null
}

# レビューできない非テキストファイルなら 0。
# 空ファイルは中身が無く害がないので非テキスト扱いにしない（-s で先に弾く）。
is_binary_file() {
  [ -s "$1" ] && ! is_text_file "$1"
}
