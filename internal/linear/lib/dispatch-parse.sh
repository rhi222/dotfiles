#!/bin/bash
# dispatch系スクリプトが共有する本文パーサ。
# 実装レーン（dispatch-cron.sh）とEMレーン（em-dispatch.sh）の両方が
# 「repo:行があるか」「PR URLがあるか」で分岐するため、ここに置く。

# dispatch_parse_repo <description> → repo（例 github.com/example-org/repo1）。無ければ非0
#
# Linearは本文中の `github.com/owner/name` を自動でmarkdownリンクに変換するため
# `repo: [github.com/o/n](<http://github.com/o/n>)` の形で保存されることがある。
# host/owner/name の3要素だけを抜き出してどちらの形式でも同じ結果にする。
dispatch_parse_repo() {
  local line repo
  line=$(grep -m1 -E '^repo:' <<<"$1") || return 1
  repo=$(grep -oE '[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' <<<"$line" | head -1)
  [[ -n "$repo" ]] || return 1
  echo "$repo"
}

# dispatch_parse_pr_url <description> → owner/name/number（例 example-org/repo1/42）。無ければ非0
# LinearはURLをmarkdownリンク化するので、リンク記法でも素のURLでも拾えるようにする
dispatch_parse_pr_url() {
  local m
  m=$(grep -oE 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+' <<<"$1" | head -1)
  [[ -n "$m" ]] || return 1
  sed -E 's#^github\.com/##' <<<"$m" | sed -E 's#/pull/#/#'
}
