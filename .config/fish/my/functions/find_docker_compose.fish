function find_docker_compose
    # ───────────────────────────────────────────────────────────────────
    # 1) Gitリポジトリ or worktree ルートを取得

    set -l repo_root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$repo_root"
        echo "Error: Not inside a Git repository." >&2
        return 1
    end

    # ───────────────────────────────────────────────────────────────────
    # 2) 一箇所にまとめたファイル名パターンと典型ディレクトリリスト
    set -l patterns docker-compose.yml docker-compose.yaml compose.yml compose.yaml
    set -l dirs \
        $repo_root \
        $repo_root/etc/docker \
        $repo_root/docker \
        $repo_root/docker-compose

    # ───────────────────────────────────────────────────────────────────
    # 3) 超高速チェック: 典型ディレクトリの下を順に探す
    for d in $dirs
        for p in $patterns
            set -l candidate "$d/$p"
            if test -f "$candidate"
                echo $candidate

                return 0
            end
        end
    end

    # ───────────────────────────────────────────────────────────────────
    # 4) 深さ制限付きサーチ (fd があれば fd、なければ find)
    if type -q fd
        # fd にパターンを渡す
        set -l fd_args --hidden --max-depth 4 --type f
        for p in $patterns
            set fd_args $fd_args --glob $p
        end
        set -l result (fd $fd_args $repo_root | head -n1)
    else
        # find 用に "-name X -o -name Y ..." を準備
        set -l name_args
        for p in $patterns
            set name_args $name_args -name $p -o
        end
        # 末尾の "-o" を削除
        set name_args $name_args[1..-2]

        set -l result (find $repo_root -maxdepth 4 -type f \( $name_args \) | head -n1)
    end

    if test -n "$result"
        echo $result
        return 0
    end

    echo "Error: Docker Compose file not found." >&2
    return 1
end