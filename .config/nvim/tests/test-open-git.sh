#!/usr/bin/env bash
# OpenGit の URL 生成テスト
# 一時 git リポジトリを作り、headless nvim で :OpenGit を実行して URL を検証する
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_LUA_DIR="$SCRIPT_DIR/../lua"
SPEC="$SCRIPT_DIR/open-git_spec.lua"

FAILED=0

run_case() {
	local desc="$1"
	local target_file="$2"
	local expected_url="$3"
	local repo_dir="$4"

	if (cd "$repo_dir" && EXPECTED_URL="$expected_url" nvim --headless -u NONE -l "$SPEC" "$CONFIG_LUA_DIR" "$target_file" 2>&1); then
		echo "ok: $desc"
	else
		echo "NG: $desc"
		FAILED=1
	fi
}

setup_repo() {
	local repo_dir="$1"
	git -C "$repo_dir" init -q -b main
	git -C "$repo_dir" config user.email "test@example.com"
	git -C "$repo_dir" config user.name "test"
	git -C "$repo_dir" remote add origin git@github.com:owner/repo.git
}

# --- case 1: リポジトリルート直下のファイル ---
TMP1="$(mktemp -d)"
trap 'rm -rf "$TMP1" "$TMP2"' EXIT
setup_repo "$TMP1"
echo "hello" > "$TMP1/file.txt"
git -C "$TMP1" add . && git -C "$TMP1" commit -qm init
HASH1="$(git -C "$TMP1" rev-parse HEAD)"
run_case "ルート直下のファイル" \
	"$TMP1/file.txt" \
	"https://github.com/owner/repo/blob/$HASH1/file.txt#L1" \
	"$TMP1"

# --- case 2: 空の .git ディレクトリを含むサブディレクトリ配下のファイル ---
# (monorepo のサブパッケージにツールが空の .git を作るケースの再現)
TMP2="$(mktemp -d)"
setup_repo "$TMP2"
mkdir -p "$TMP2/apps/sub/src"
echo "hello" > "$TMP2/apps/sub/src/file.txt"
git -C "$TMP2" add . && git -C "$TMP2" commit -qm init
mkdir "$TMP2/apps/sub/.git" # 空の .git ディレクトリ（有効なリポジトリではない）
HASH2="$(git -C "$TMP2" rev-parse HEAD)"
run_case "空の .git を含むサブディレクトリ配下のファイル" \
	"$TMP2/apps/sub/src/file.txt" \
	"https://github.com/owner/repo/blob/$HASH2/apps/sub/src/file.txt#L1" \
	"$TMP2"

exit "$FAILED"
