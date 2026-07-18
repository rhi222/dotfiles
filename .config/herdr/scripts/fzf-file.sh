#!/usr/bin/env bash
# herdr 'prefix+f' helper: popup内でfzfファイル検索 → 選択パスを呼び出し元ペインに挿入
# tmux の bind f (fzf-file.sh) 相当。
#
# herdr の popup コマンドは #{pane_current_path} 等のフォーマット展開を持たず、
# また popup には HERDR_PANE_ID が渡らないため、代わりに以下の env を使う:
#   HERDR_ACTIVE_PANE_ID  : popup を起動した下地ペインの pane_id (送信先)
#   HERDR_ACTIVE_PANE_CWD : そのペインの作業ディレクトリ (検索開始地点)

set -eu

start_dir="${HERDR_ACTIVE_PANE_CWD:-$HOME}"
pane_id="${HERDR_ACTIVE_PANE_ID:-}"

if [ -z "$pane_id" ]; then
    echo "HERDR_ACTIVE_PANE_ID が空です。popup 経由で実行してください。" >&2
    exit 1
fi

cd "$start_dir" || exit 0

if command -v fd >/dev/null 2>&1; then
    list_cmd=(fd --type f --hidden --exclude .git)
else
    list_cmd=(find . -type f -not -path '*/.git/*')
fi

# popup 自体が枠付きなので、fzf は枠内をそのまま使う（tmux の --tmux 指定は不要）
selected=$("${list_cmd[@]}" | fzf --layout reverse)
[ -n "$selected" ] || exit 0

# tmux の send-keys 同様、Enter は送らずリテラルのパスだけ挿入する
herdr pane send-text "$pane_id" "$selected"
