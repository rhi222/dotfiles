# docker の不要リソースを掃除する（軽/重 2段プリセット）
#
# 稼働中コンテナは一切停止しない。一覧を表示するだけで、停止は手動判断とする。
# named volume も削除しない（volume prune に -a を付けない）。DB データを守るため。
function dclean --description 'docker の不要リソースを掃除する（軽/重プリセット）'
    set -l mode light
    set -l action clean

    for a in $argv
        switch $a
            case -a --all
                set mode heavy
            case --status
                set action status
            case --refresh
                set action refresh
            case -h --help
                __dclean_usage
                return 0
            case '*'
                echo "dclean: 不明な引数: $a" >&2
                __dclean_usage >&2
                return 2
        end
    end

    if not docker info >/dev/null 2>&1
        echo "Docker が起動していません" >&2
        return 1
    end

    if test $action = refresh
        __docker_clean_stats --update
        return $status
    end

    # プレビューは削除直前の実データで出す。手動実行なので 5 秒待って構わない。
    __docker_clean_stats --update
    __dclean_preview $mode

    test $action = status; and return 0

    # プロンプトは read -P に任せる。自分で printf してから引数なしの read を呼ぶと、
    # read が自前の `read>` プロンプトを描画して printf の出力を上書きしてしまう。
    # -P のプロンプトは stdin が tty でないと出ないため、テストは表示ではなく
    # 挙動（y/yes/Y で実行、それ以外で中止）で検証する。
    read -l -P '実行しますか? [y/N] ' ans
    if not string match -qir '^y(es)?$' -- $ans
        echo 中止しました
        return 0
    end

    __dclean_run $mode
    set -l rc $status
    __docker_clean_stats --update
    return $rc
end

function __dclean_usage --description 'dclean の使い方を表示する'
    echo '使い方: dclean [-a|--all] [--status] [--refresh] [-h|--help]'
    echo ''
    echo '  (引数なし)      軽掃除: 停止コンテナ / dangling image / 匿名 volume /'
    echo '                  使われていない build cache を削除する'
    echo '  -a, --all       重掃除: 上記 + 未使用 image 全部 + 共有ぶんも含む build cache 全部'
    echo '  --status        現状の集計と稼働中コンテナ一覧のみ表示（削除しない）'
    echo '  --refresh       キャッシュ更新のみ（起動時通知が background で使う）'
    echo '  -h, --help      この使い方を表示する'
    echo ''
    echo '  named volume は軽・重どちらでも削除しない。消すときは docker volume rm を使う。'
    echo '  稼働中コンテナも停止しない。一覧を見て手動で判断する。'
end

# buildx のビルダー名を列挙する。
#
# `docker builder prune` は docker buildx prune のエイリアスで、--builder を
# 付けないとカレントビルダーしか掃除しない。docker-container ドライバのビルダーと
# daemon 側の default ビルダーは別のキャッシュを持つ（実測で 11.2GB と 6.8GB）ため、
# 両方を対象にしないと片方が永久に残る。
#
# 列挙できなかった場合は空を返す。呼び出し側は --builder を付けずにカレントビルダーだけを扱う。
function __dclean_builders --description 'buildx のビルダー名を列挙する'
    docker buildx ls --format json 2>/dev/null | jq -r '.Name' 2>/dev/null
end

function __dclean_df_field --description 'キャッシュした df から指定種別のフィールドを取り出す'
    set -l cache (__docker_clean_cache_file)
    jq -r --arg t "$argv[1]" --arg f "$argv[2]" \
        '.df[]? | select(.Type == $t) | .[$f] // ""' $cache 2>/dev/null
end

# プレビューの1行を整形する。
# string pad は East Asian の文字幅を考慮するため日本語ラベルでも桁が揃う。
# printf の %-18s はバイト数で詰めるので日本語では崩れる。
function __dclean_row --description 'プレビューの1行を整形して出力する'
    set -l label (string pad -r -w 18 -- $argv[1])
    set -l n (string pad -w 4 -- $argv[2])
    set -l out "  $label$n 件   $argv[3]"
    test (count $argv) -ge 4; and set out "$out   $argv[4]"
    echo $out
end

function __dclean_preview --description 'dclean のプレビューを表示する'
    set -l mode $argv[1]
    set -l label 軽
    test $mode = heavy; and set label 重

    echo "docker 掃除プレビュー（$label）"

    set -l known 0

    # 停止コンテナ
    set -l stopped_n (count (docker ps -a -q -f status=exited -f status=created 2>/dev/null))
    set -l stopped_b (__docker_clean_size_to_bytes (__dclean_df_field Containers Reclaimable))
    or set stopped_b 0
    __dclean_row 停止コンテナ $stopped_n (__docker_clean_format_bytes $stopped_b)
    set known (math "$known + $stopped_b")

    # image
    if test $mode = heavy
        set -l total (__dclean_df_field Images TotalCount)
        set -l active (__dclean_df_field Images Active)
        set -l img_n (math "$total - $active")
        set -l img_b (__docker_clean_size_to_bytes (__dclean_df_field Images Reclaimable))
        or set img_b 0
        __dclean_row '未使用 image' $img_n (__docker_clean_format_bytes $img_b)
        set known (math "$known + $img_b")
    else
        set -l img_n (count (docker images -f dangling=true -q 2>/dev/null))
        __dclean_row 'dangling image' $img_n - '※共有レイヤのため事前見積り不可'
    end

    # volume（匿名のみ。64桁hex名で判定する）
    set -l vol_n (docker volume ls -q -f dangling=true 2>/dev/null | string match -r '^[0-9a-f]{64}$' | count)
    set -l vol_b (__docker_clean_size_to_bytes (__dclean_df_field 'Local Volumes' Reclaimable))
    or set vol_b 0
    __dclean_row '未使用 volume' $vol_n (__docker_clean_format_bytes $vol_b) '※ named volume は対象外'
    set known (math "$known + $vol_b")

    # build cache
    #
    # 件数は全ビルダーを合算する（df の Build Cache は default ビルダーの分しか出ない）。
    # buildx du に --filter until= を渡しても無視されるためフィルタは付けない。
    #
    # サイズは軽モードでは出さない。buildx du の Size は共有レイヤを含むうえ、軽モードは
    # そのうち「使われていないぶん」だけを消すため、合算すると実際の回収量と桁が変わる
    # （246件/5.4GB と表示して実際の回収が 0B になった）。df の Build Cache Reclaimable は
    # default ビルダーの分しか見ないので代わりにもならない。実際の回収量は実行後の
    # `回収:` 行で確認する。
    set -l sizes
    set -l builders (__dclean_builders)
    if test (count $builders) -eq 0
        set sizes (docker buildx du --format json 2>/dev/null | jq -r 'select(.Reclaimable == true) | .Size')
    else
        for b in $builders
            set -a sizes (docker buildx du --builder $b --format json 2>/dev/null | jq -r 'select(.Reclaimable == true) | .Size')
        end
    end
    set -l bc_n (count $sizes)

    if test $mode = heavy
        set -l bc_b 0
        if test $bc_n -gt 0
            set bc_b (__docker_clean_size_to_bytes $sizes)
            or set bc_b 0
        end
        __dclean_row 'build cache' $bc_n 最大(__docker_clean_format_bytes $bc_b) '※全ビルダー合算'
        set known (math "$known + $bc_b")
    else
        __dclean_row 'build cache' $bc_n - '※全ビルダー合算 / うち未使用ぶんのみ削除'
    end

    echo '  ──────────────────────────────'
    echo "  回収見込み 最大 約 "(__docker_clean_format_bytes $known)
    if test $mode = heavy
        echo '  （buildx du のサイズは共有レイヤを含むため実際はこれより少ない）'
    else
        echo '  （image と build cache の回収量は事前に確定できないため未計上。'
        echo '    実際の回収量は実行後の「回収:」行を見る）'
    end
    echo ''

    echo '稼働中コンテナ（停止は手動判断）'
    set -l long (__docker_clean_stats --long-running)
    set -l rows (__dclean_classify_running $long)
    if test (count $rows) -eq 0
        echo '  （閾値を超えて稼働しているコンテナはありません）'
    else
        for row in $rows
            set -l r (string split \t -- $row)
            # タグのパディングは括弧の外側に入れる（[main  ] ではなく [main]  ）。
            # wt / wtd の一覧と同じ規約。ASCII なので string pad の East Asian 幅も絡まない。
            set -l tag (string pad -r -w 13 -- "[$r[1]]")
            set -l note ''
            test "$r[6]" = true; and set note '   ※--rm: 停止で削除されます'
            printf '  %s%-36s Up %s%s\n' $tag $r[2] (__dclean_humanize_uptime $r[3]) $note
            # orphan だけ理由を添える。どの worktree の残骸か分かるのが実用上の価値。
            test "$r[1]" = orphan; and printf '               └ working_dir なし: %s\n' $r[5]
        end
    end
    # 除外パターンで非表示になっている閾値超えコンテナがあることを示す。
    # 出さないと docker ps と件数が合わず「表示に不足がある」ように見える。
    set -l excluded_n (count (__docker_clean_stats --long-running --excluded))
    if test $excluded_n -gt 0
        echo "  （除外 $excluded_n 件 — docker_clean_ignore_patterns で非表示）"
    end
    # 止めると判断したらコピペで済むよう、種別ごとにコマンドを出す。実行はしない
    # （停止は手動判断のまま）。
    #
    # 種別で分けるのは、停止の可逆性がまるで違うため。
    #   compose … レシピが docker-compose.yml に残るので up で戻せる
    #   orphan  … working_dir ごと消えているので戻せない（が確実な停止候補）
    #   standalone … レシピが docker 側に残らない。--rm なら停止＝即削除
    #
    # compose 系は `docker compose -p <project> down` にする。`-p` を付ければ
    # compose ファイル無し・任意の cwd から label 経由でプロジェクトを解決でき、
    # compose が作った network も一緒に回収される。
    #
    # --refresh は最終行に独立して出す。起動時通知はキャッシュしか読まないため、
    # 停止しただけでは TTL（既定6h）が切れるまで古い件数を通知し続ける。
    if test (count $rows) -gt 0
        set -l orphan_projects
        set -l compose_projects
        set -l standalone_names
        set -l standalone_rm 0
        for row in $rows
            set -l r (string split \t -- $row)
            switch $r[1]
                case orphan
                    contains -- $r[4] $orphan_projects; or set -a orphan_projects $r[4]
                case compose
                    contains -- $r[4] $compose_projects; or set -a compose_projects $r[4]
                case standalone
                    set -a standalone_names $r[2]
                    test "$r[6]" = true; and set standalone_rm 1
            end
        end

        echo ''
        echo '  停止する場合（コピペ用）:'
        if test (count $orphan_projects) -gt 0
            echo '  # orphan（working_dir が消えているため up では戻せません）'
            for p in $orphan_projects
                echo "  docker compose -p $p down"
            end
        end
        if test (count $compose_projects) -gt 0
            echo '  # compose（up で戻せます）'
            for p in $compose_projects
                echo "  docker compose -p $p down"
            end
        end
        if test (count $standalone_names) -gt 0
            if test $standalone_rm -eq 1
                echo '  # standalone（※--rm のコンテナは停止で削除されます）'
            else
                echo '  # standalone'
            end
            echo "  docker container stop $standalone_names"
        end
        echo '  dclean --refresh'
    end
    echo ''
end

# --long-running の行に種別を前置する。
# 出力の列: kind<TAB>name<TAB>秒<TAB>compose_project<TAB>compose_dir<TAB>auto_remove
#
# 表示ループとコピペ用コマンドのループが同じ分類を使えるよう、判定を1箇所に寄せる。
# 列が足りない行（種別列を持たない旧キャッシュ）でも落とさず standalone に倒す。
function __dclean_classify_running --description '稼働コンテナ行に種別を前置する'
    for line in $argv
        set -l f (string split \t -- $line)
        test (count $f) -ge 3; or continue
        set -l project ''
        test (count $f) -ge 4; and set project $f[4]
        set -l dir ''
        test (count $f) -ge 5; and set dir $f[5]
        set -l autorm ''
        test (count $f) -ge 6; and set autorm $f[6]
        echo (string join \t (__docker_clean_container_kind $project $dir) $f[1] $f[3] $project $dir $autorm)
    end
end

# モードに応じた prune を順に実行する。
# 1 つのコマンドが失敗しても残りは続行し、最後に失敗件数を報告する。
function __dclean_run --description 'dclean の削除を実行する'
    set -l mode $argv[1]

    # NOTE: volume prune には軽・重どちらでも -a を付けない。
    # -a なしなら匿名 volume だけが対象になり、named volume（DB データ）が守られる。
    set -l cmds 'container prune -f'
    if test $mode = heavy
        set -a cmds 'image prune -a -f'
    else
        set -a cmds 'image prune -f'
    end
    set -a cmds 'volume prune -f'

    # build cache は全ビルダーぶん実行する（__dclean_builders のコメント参照）。
    #
    # `--filter until=<duration>` は使わない。実測で docker ドライバ・docker-container
    # ドライバのどちらでも `Total: 0B` になり、7日以上前のレコードが残っていても
    # 一切回収されなかった。フィルタなしなら 5.142GB 回収でき、df の Reclaimable も
    # 0B になる。軽と重の区別は -a の有無だけで付ける。
    #   軽 (-a なし): 使われていないキャッシュを消す
    #   重 (-a あり): 共有・参照されているキャッシュも消す
    set -l bc_base 'builder prune -f'
    test $mode = heavy; and set bc_base 'builder prune -a -f'
    set -l builders (__dclean_builders)
    if test (count $builders) -eq 0
        set -a cmds $bc_base
    else
        for b in $builders
            set -a cmds "$bc_base --builder $b"
        end
    end

    set -l failed 0
    set -l reclaimed 0

    for c in $cmds
        set -l parts (string split ' ' -- $c)
        echo "→ docker $c"
        set -l out (docker $parts 2>&1)
        if test $status -ne 0
            echo "  失敗: docker $c"
            printf '  %s\n' $out >&2
            set failed (math "$failed + 1")
            continue
        end

        for line in $out
            printf '  %s\n' $line
            # docker prune は "Total reclaimed space: 2.5GB"、
            # buildkit の prune は "Total:\t6.776GB" を出す。どちらも拾う。
            set -l m (string match -r '^(?:Total reclaimed space:|Total:)\s*(.+)$' -- (string trim -- $line))
            if test (count $m) -ge 2
                set -l b (__docker_clean_size_to_bytes $m[2] 2>/dev/null)
                and set reclaimed (math "$reclaimed + $b")
            end
        end
    end

    echo ''
    echo "回収: "(__docker_clean_format_bytes $reclaimed)

    if test $failed -gt 0
        echo "$failed 件のコマンドが失敗しました" >&2
        return 1
    end
    return 0
end

function __dclean_humanize_uptime --description '秒数を「23 hours」形式にする'
    set -l s $argv[1]
    set -l h (math "floor($s / 3600)")
    if test $h -lt 24
        echo "$h hours"
    else
        echo (math "floor($h / 24)")" days"
    end
end
