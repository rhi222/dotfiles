# コンテナの由来を判定する。
#
# 使い方: __docker_clean_container_kind <compose_project> <compose_dir>
#   compose_project  com.docker.compose.project label（無ければ空）
#   compose_dir      com.docker.compose.project.working_dir label（無ければ空）
#
# 返す種別:
#   standalone  compose 管理外（docker run 由来）
#   orphan      compose 管理だが working_dir が消えている
#   compose     compose 管理で working_dir が存在する
#
# 停止のリスクが種別で違うため分ける。compose はレシピが docker-compose.yml に
# 残るので `docker compose up` で戻せる。standalone はレシピが docker 側に一切
# 残らず、`--rm` 付きなら停止＝即削除になる（実機の example-org-mcp がこれ）。
# orphan は置き場所ごと消えているので確実な停止候補になる。
#
# **判定順が要点。compose_dir が空のときは orphan にせず compose に倒す。**
# orphan は削除を伴う `docker compose down` を案内する側なので、孤児だと
# 証明できないものを孤児扱いしてはいけない。
function __docker_clean_container_kind --description 'コンテナの由来を判定する'
    set -l project ''
    test (count $argv) -ge 1; and set project $argv[1]
    set -l dir ''
    test (count $argv) -ge 2; and set dir $argv[2]

    if test -z "$project"
        echo standalone
        return 0
    end
    if test -n "$dir"; and not test -d "$dir"
        echo orphan
        return 0
    end
    echo compose
    return 0
end
