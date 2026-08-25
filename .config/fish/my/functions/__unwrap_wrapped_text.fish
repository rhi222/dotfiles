# 折返しで改行が混入したテキストを1行へ戻す（stdin → stdout）
#
# 端末に出た「本来1行」のコマンドやURLをコピーすると改行が入る。入り方は2種類あり、
# 連結の仕方が逆になる。
#
#   ① アプリ側の折返し（Claude Code のコードブロックなど）
#      自前の描画幅で「単語境界」を切り、継続行にインデントを付けて出力する。
#      端末バッファ上の本物の改行なので、コピー機構をどう設定しても復元できない。
#      → 継続行の先頭空白を落として **空白1個** で連結する。
#
#   ② 端末のソフト折返し
#      ペイン幅でトークンの途中を切る。継続行にインデントは付かない。
#      → **連結子なし** でつなぐ。
#
# **判定は「継続行が空白で始まるか」だけでよい。** ①は必ず始まり、②は必ず始まらない。
# コピー元の端末幅を知る必要がないので、幅の違うペインやウィンドウから貼っても同じに効く。
#
# 行末の空白は連結前に必ず落とす。端末は行をパディングするため、残すと ② で
# トークンの途中に空白が入る。副作用として ② の折返し位置がちょうど空白に当たった
# ケースはその空白を復元できない（端末側の行末トリムで既に失われている）。
function __unwrap_wrapped_text --description 折返し由来の改行を畳んで1行にする
    # `read` は IFS で先頭の空白を落としてしまう。先頭空白が判定の唯一の材料なので、
    # stdin を丸ごと受けて自分で改行分割する。
    set -l input (cat | string collect --no-trim-newlines)
    set -l parts

    for line in (string split \n -- $input)
        # CR は行末トリムの対象外なので明示的に落とす（CRLF 経由のコピー）
        set line (string replace -a \r '' -- $line)
        # 端末のパディングを連結に持ち込まない
        set -l trimmed (string trim --right -- $line)

        # 空行は連結の判定材料にしない。次の非空行の先頭空白でその行を判定する
        test -z "$trimmed"; and continue

        if test (count $parts) -eq 0
            set -a parts (string trim --left -- $trimmed)
            continue
        end

        if string match -qr '^[ \t]' -- $trimmed
            # ① 単語境界で切れている。インデントを落として空白1個でつなぐ
            set parts[-1] "$parts[-1] "(string trim --left -- $trimmed)
        else
            # ② トークンの途中で切れている。そのまま詰める
            set parts[-1] "$parts[-1]$trimmed"
        end
    end

    test (count $parts) -eq 0; and return 0
    echo -- $parts[1]
end
