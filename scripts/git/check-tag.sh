#!/usr/bin/env bash
# check-tag.sh — 2つのタグが同じcommitを指すか確認する。
#
#   bash scripts/git/check-tag.sh <repo_name> <tag1> <tag2>
#
# repo_name は ghq 管理下から解決する。org名をこのファイルへ書かない。
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <repo_name> <tag1> <tag2>" >&2
  exit 2
fi

repo_name="$1"
tag1="$2"
tag2="$3"

repo=$(ghq list -p | grep -m1 "/${repo_name}\$") || {
  echo "Repo not found in ghq: $repo_name" >&2
  exit 4
}

cd "$repo"

git fetch --tags >/dev/null 2>&1

for tag in "$tag1" "$tag2"; do
  git rev-parse --verify "$tag^{commit}" >/dev/null 2>&1 || {
    echo "Tag not found: $tag" >&2
    exit 3
  }
done

hash1=$(git rev-parse --verify "$tag1^{commit}")
hash2=$(git rev-parse --verify "$tag2^{commit}")

echo "$tag1 -> $hash1"
echo "$tag2 -> $hash2"

if [ "$hash1" = "$hash2" ]; then
  echo "OK: both tags point to the same commit."
else
  echo "NG: different commits."
  exit 1
fi
