#!/usr/bin/env bash
# tmux-resurrect post-save-layout hook
#
# ps save strategy が zombie プロセス ([fish] <defunct> 等) と実コマンドを
# 両方出力し、保存ファイルのタブ区切りフォーマットを壊す問題を修正する。
#
# Before:
#   pane\t...\tnvim\t:[fish] <defunct>
#   /tmp/.mount_nvimXXX/usr/bin/nvim file.txt
#
# After:
#   pane\t...\tnvim\t:/tmp/.mount_nvimXXX/usr/bin/nvim file.txt

file="$1"
[ -f "$file" ] || exit 0

awk '
/^pane/ && /:\[[^\]]*\] <defunct>$/ {
    # pane行が <defunct> で終わっている → 次の行に実コマンドがあるはず
    saved = $0
    if (getline nextline > 0) {
        if (nextline ~ /^pane/ || nextline ~ /^window/ || nextline ~ /^state/) {
            # 次の行も構造行 → 実コマンドなし、そのまま出力
            print saved
            print nextline
        } else {
            # 次の行が実コマンド → <defunct> を除去し実コマンドを連結
            # NOTE: sub() の第2引数に nextline を渡すと & や \ が展開されるため、
            #       末尾を ":" だけに置換してから文字列連結する。
            sub(/:\[[^\]]*\] <defunct>$/, ":", saved)
            print saved nextline
        }
    } else {
        # ファイル末尾 → そのまま出力
        print saved
    }
    next
}
{ print }
' "$file" > "${file}.tmp"

# awk の出力が空または元ファイルより極端に小さい場合は上書きしない
if [ ! -s "${file}.tmp" ]; then
    rm -f "${file}.tmp"
    exit 0
fi

mv "${file}.tmp" "$file"
