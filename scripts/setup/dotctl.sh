#!/bin/bash
# dotctl をリポジトリからビルドして ~/.local/bin へ入れる。
#
#   bash scripts/setup/dotctl.sh                # テスト -> ビルド -> 入れ替え
#   bash scripts/setup/dotctl.sh --skip-tests   # 緊急時にテストを飛ばす
#
# 環境変数:
#   DOTCTL_REPO  ビルド元のリポジトリ（既定: このスクリプトの祖父）
#   DOTCTL_BIN   出力先（既定: ~/.local/bin/dotctl）
#   DOTCTL_GO    go の実行ファイル名（既定 go。テストが「go が無い」経路を作る）
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

# ~/scripts のように scripts/ 自体が symlink の場合も、物理pathを基準にrepo rootを
# 求める。論理pathのまま `..` へ進むと $HOME をrepoと誤認し、go test ./... が落ちる。
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO="${DOTCTL_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BIN="${DOTCTL_BIN:-$HOME/.local/bin/dotctl}"

# **「go が無い」経路は PATH を削って作れない。** CI の runner は
# /usr/bin:/bin にも go を持っており、それで CI だけ落ちた。存在しない名前を
# 渡せば PATH の中身に依存せず不在を作れる。
GO="${DOTCTL_GO:-go}"

SKIP_TESTS=0
if [ "${1:-}" = "--skip-tests" ]; then
  SKIP_TESTS=1
elif [ -n "${1:-}" ]; then
  echo "使い方: setup-dotctl.sh [--skip-tests]" >&2
  exit 2
fi

# Go は mise 導入後にしか無い。**bootstrap の循環依存を避けるため、
# ここが無ければ素直に失敗する**（dotfilesLink.sh はこれを必須にしない）。
if ! command -v "$GO" >/dev/null 2>&1; then
  echo "setup-dotctl: go が見つからない。mise で入れる: mise install go" >&2
  exit 1
fi

# HEAD・Go toolchain・Go sourceがすべて同じなら、毎日のtest/buildを省く。
# sourceはdirtyの有無ではなく内容のfingerprintで比べる。未コミットのGo変更が
# あっても、一度その内容をbuild済みなら次回はskipできる。
commit="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
current_go="$("$GO" version 2>/dev/null | awk '{print $3}')"

source_fingerprint() {
  (
    cd "$REPO" || exit 1
    git ls-files -co --exclude-standard -- '*.go' go.mod go.sum |
      LC_ALL=C sort |
      while IFS= read -r file; do
        printf '%s\0' "$file"
        git hash-object "$file"
      done |
      git hash-object --stdin
  )
}

if ! source_hash="$(source_fingerprint)"; then
  echo "setup-dotctl: Go sourceのfingerprintを計算できない" >&2
  exit 1
fi
installed_commit=""
installed_go=""
installed_source_hash=""
if [ -x "$BIN" ]; then
  installed_commit="$("$BIN" version 2>/dev/null | awk 'NR == 1 && $1 == "dotctl" { print $2 }')"
  installed_source_hash="$("$BIN" version 2>/dev/null | awk 'NR == 1 && $1 == "dotctl" { print $3 }')"
  installed_go="$("$GO" version -m "$BIN" 2>/dev/null | awk 'NR == 1 { print $2 }')"
fi
if [ -n "$current_go" ] && [ "$installed_commit" = "$commit" ] &&
  [ "$installed_go" = "$current_go" ] && [ "$installed_source_hash" = "$source_hash" ]; then
  echo "setup-dotctl: already current ($commit, $current_go), skipping"
  exit 0
fi

if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "setup-dotctl: テストを skip した（--skip-tests）"
else
  # -short で unit だけに絞る。実 git リポジトリを作る integration は
  # run-tests.sh と CI の担当で、日次のビルド前ゲートには重すぎる。
  if ! (cd "$REPO" && "$GO" test -short ./...); then
    echo "setup-dotctl: テストが落ちたのでビルドしない（既存バイナリはそのまま）" >&2
    exit 1
  fi
fi

# test中にgo.sumやGo sourceが変わる場合がある。特に別agentが同じworktreeを
# 編集していると、test前のhashを埋めてtest後の内容をbuildし、次回また必ず
# rebuildするバイナリができる。build入力を確定する直前に取り直す。
if ! source_hash="$(source_fingerprint)"; then
  echo "setup-dotctl: Go sourceのfingerprintを再計算できない" >&2
  exit 1
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

pkg="github.com/rhi222/dotfiles/internal/buildinfo"

if ! (cd "$REPO" && "$GO" build \
  -ldflags "-X $pkg.Commit=$commit -X $pkg.Repo=$REPO -X $pkg.SourceHash=$source_hash" \
  -o "$tmp" ./cmd/dotctl); then
  echo "setup-dotctl: ビルドが落ちた（既存バイナリはそのまま）" >&2
  exit 1
fi

# build中にも入力が変わったなら、埋め込んだhashと実際の内容が一致しない。
# そのバイナリを配らず、既存を保ったまま次回の再実行へ倒す。
if ! final_source_hash="$(source_fingerprint)" || [ "$final_source_hash" != "$source_hash" ]; then
  echo "setup-dotctl: build中にGo sourceが変わったため更新しない。再実行してください" >&2
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
