# `git wt` の出力（ヘッダ除去済み）を fzf 表示用の行に整形する
#
# 出力形式: `<マーカー> [<タグ>] <branch> <path> <sha>`
# タグは1トークンに収まるよう括弧の外側でパディングする（内側に空白を入れると
# wt/wtd 側の awk のフィールド番号がずれる）。
#
# タグの意味:
#   main   … メインworktree（第1引数のパスと一致する行）
#   .wt    … `git wt` が作る `.wt/` 配下
#   claude … Claude Code が作る `.claude/worktrees/` 配下
#   wt     … それ以外の場所にあるリンクworktree
#
# **メイン判定はパス文字列ではなく `__wt_main_path` の実パスとの一致で行う。**
# 以前は「パスに `.wt` を含むか」だけで見ていたため、`.claude/worktrees/` 配下の
# worktree が main と表示され、逆にメインworktreeのパスに `.wt` が含まれると
# .wt と表示されていた。
#
# 第1引数が空（gitリポジトリ外など）の場合は、置き場所で分類できない行を main に
# 倒す。判定不能なときに全行が wt になるより、従来の見え方に寄せる方が混乱が少ない。
function __wt_format_rows --argument-names main_path
    awk -v main_path="$main_path" '
        function tag_for(path) {
            if (main_path != "" && path == main_path) return "main"
            if (path ~ /\/\.wt\//) return ".wt"
            if (path ~ /\/\.claude\/worktrees\//) return "claude"
            return (main_path == "") ? "main" : "wt"
        }
        {
            if ($1 == "*") printf("* %-8s %s %s %s\n", "[" tag_for($2) "]", $3, $2, $4)
            else           printf("  %-8s %s %s %s\n", "[" tag_for($1) "]", $2, $1, $3)
        }
    '
end
