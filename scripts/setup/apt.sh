#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/apt-packages.txt"

if [ ! -f "$PACKAGES_FILE" ]; then
  echo "apt-packages.txt not found" >&2
  exit 1
fi

# Ubuntu標準のgitは古いので、公式メンテナのPPAから最新版を入れる。
# 登録済みなら何もしない。以後はdaily-updateのapt upgradeで追従する
sudo add-apt-repository -y -n ppa:git-core/ppa
sudo apt update
# Strip `#`-prefixed comments and blank lines so future annotations don't
# leak into the package list.
grep -vE '^\s*(#|$)' "$PACKAGES_FILE" | xargs sudo apt install -y
