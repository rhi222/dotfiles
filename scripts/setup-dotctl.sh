#!/bin/bash
# dotctl をリポジトリからビルドして ~/.local/bin へ入れる。
#
#   bash scripts/setup-dotctl.sh                # テスト -> ビルド -> 入れ替え
#   bash scripts/setup-dotctl.sh --skip-tests   # 緊急時にテストを飛ばす
#
# 環境変数:
#   DOTCTL_REPO  ビルド元のリポジトリ（既定: このスクリプトの親）
#   DOTCTL_BIN   出力先（既定: ~/.local/bin/dotctl）
#
# **失敗しても既存バイナリを壊さないことが最優先。** cron と hook が dotctl 越しに
# 動くようになると、「ビルドが落ちて実行ファイルが消える」は自動化が丸ごと止まる
# 事故になる。そのため出力先と同じディレクトリに一時ファイルを作り、
# テスト・ビルド・起動確認の全部を通ったものだけを rename で差し替える
# （同一ファイルシステム内なのでアトミックに入れ替わる）。
#
# バイナリはリポジトリへコミットしない（.gitignore）。
#
# **-ldflags で commit と repo を埋め込むのが version skew 検知の土台。**
# git pull 後に再ビルドしなければ、cron と hook は古いバイナリを黙って実行し
# 続ける（daily-update.sh が古い installs/<tool>/ の gh を掴んだ事故と同型）。
# 埋め込んだ値と repo HEAD がずれていたら dotctl 自身が stderr へ1行警告する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${DOTCTL_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BIN="${DOTCTL_BIN:-$HOME/.local/bin/dotctl}"

SKIP_TESTS=0
if [ "${1:-}" = "--skip-tests" ]; then
  SKIP_TESTS=1
elif [ -n "${1:-}" ]; then
  echo "使い方: setup-dotctl.sh [--skip-tests]" >&2
  exit 2
fi

# Go は mise 導入後にしか無い。**bootstrap の循環依存を避けるため、
# ここが無ければ素直に失敗する**（dotfilesLink.sh はこれを必須にしない）。
if ! command -v go >/dev/null 2>&1; then
  echo "setup-dotctl: go が見つからない。mise で入れる: mise install go" >&2
  exit 1
fi

if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "setup-dotctl: テストを skip した（--skip-tests）"
else
  # -short で unit だけに絞る。実 git リポジトリを作る integration は
  # run-tests.sh と CI の担当で、日次のビルド前ゲートには重すぎる。
  if ! (cd "$REPO" && go test -short ./...); then
    echo "setup-dotctl: テストが落ちたのでビルドしない（既存バイナリはそのまま）" >&2
    exit 1
  fi
fi

BIN_DIR="$(dirname "$BIN")"
mkdir -p "$BIN_DIR" || {
  echo "setup-dotctl: 出力先を作れない: $BIN_DIR" >&2
  exit 1
}

# 出力先と同じディレクトリに作る。/tmp からの mv だとファイルシステムを
# またいでコピーになり、途中で切れた中間状態が出力先に見える瞬間がある。
tmp="$(mktemp "$BIN_DIR/.dotctl.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT

commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
pkg="github.com/rhi222/dotfiles/internal/buildinfo"

if ! (cd "$REPO" && go build \
  -ldflags "-X $pkg.Commit=$commit -X $pkg.Repo=$REPO" \
  -o "$tmp" ./cmd/dotctl); then
  echo "setup-dotctl: ビルドが落ちた（既存バイナリはそのまま）" >&2
  exit 1
fi

chmod +x "$tmp"

# 起動確認。**ビルドが通っても動かないことがある**（リンク時に解決される
# 依存の欠落など）ので、置き換える前に1回呼ぶ。
if ! "$tmp" version >/dev/null 2>&1; then
  echo "setup-dotctl: ビルドしたバイナリが起動しない（既存バイナリはそのまま）" >&2
  exit 1
fi

mv "$tmp" "$BIN" || {
  echo "setup-dotctl: 入れ替えに失敗した: $BIN" >&2
  exit 1
}
trap - EXIT

echo "setup-dotctl: $BIN を更新した（$commit）"
