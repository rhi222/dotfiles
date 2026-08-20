#!/bin/bash
# 信頼済み owner の判定。skill-add.sh と setup-claude-skills.sh の両方から source する。
#
# 片方だけに置くと bootstrap 経路（setup-claude-skills.sh を直に叩く）から
# allowlist 外が入る。判定が確定する唯一の瞬間は owner を渡すところなので、
# そこで落とす。
#
# **ファイルが無ければ拒否する（fail-closed）。** secret-scan.sh の辞書とは逆に
# 倒している。辞書不在で commit できないのは困るが、allowlist 不在で skill が
# 入らないのは機能が欠けるだけで害がない。
#
# Env:
#   TRUSTED_SKILL_OWNERS_FILE  allowlist の場所（既定 <scripts>/trusted-skill-owners.txt）

trusted_skill_owners_file() {
  if [ -n "${TRUSTED_SKILL_OWNERS_FILE:-}" ]; then
    printf '%s' "$TRUSTED_SKILL_OWNERS_FILE"
    return 0
  fi
  printf '%s/trusted-skill-owners.txt' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

is_trusted_owner() {
  local owner="$1" file line
  file="$(trusted_skill_owners_file)"
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    # 前後の空白を落とす
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [ "$line" = "$owner" ] && return 0
  done <"$file"
  return 1
}

require_trusted_owner() {
  local repo="$1" owner="${1%%/*}"
  is_trusted_owner "$owner" && return 0
  cat >&2 <<MSG
Error: owner '$owner' は trusted-skill-owners.txt に無い
  gh skill の自動同期は信頼済み owner に限定している（毎日レビューなしで更新されるため）。
  vendoring して取り込む:
    bash scripts/skill-vendor.sh add $repo <sub-path> [name]
MSG
  return 1
}
