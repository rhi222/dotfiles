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

# em_is_em_lane <issue-json>
# EMレーンが扱う対象なら0。実装レーンの担当・委譲不可なら非0。
#
# 判定は3つ。role:manager を持つ / ai:blocked-human を持たない /
# 本文に repo: 行もPR URLも無い。ラベルを判別子に使うのは、これが
# パイプライン上の位置ではなく「どちらのランナーが扱えるか」という
# 属性だから（ai:blocked-human がstateと直交しているのと同じ理由）
#
# `A && return 1` と書かないこと。Aが失敗するとリスト全体が非0を返し、
# set -e が効く文脈では関数ではなくスクリプトごと落ちる。必ず if で書く
em_is_em_lane() {
  local issue="$1" desc
  if ! jq -e '[.labels.nodes[].name] | index("role:manager")' <<<"$issue" >/dev/null 2>&1; then
    return 1
  fi
  if jq -e '[.labels.nodes[].name] | index("ai:blocked-human")' <<<"$issue" >/dev/null 2>&1; then
    return 1
  fi
  desc=$(jq -r '.description // ""' <<<"$issue")
  if dispatch_parse_repo "$desc" >/dev/null 2>&1; then
    return 1
  fi
  if dispatch_parse_pr_url "$desc" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}
