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
    # NOTE: set -l はブロックスコープ。if/else 内で宣言すると外で参照不可になるため、関数スコープで宣言する。
    set -l result
    if type -q fd
        set -l fd_glob "{"(string join , $patterns)"}"
        set result (fd --hidden --max-depth 4 --max-results 1 --type f --glob $fd_glob $repo_root)
    else
        set -l name_args
        for p in $patterns
            set name_args $name_args -name $p -o
        end
        set name_args $name_args[1..-2]

        # -print -quit で最初の1件を出力して即終了
        set result (find $repo_root -maxdepth 4 -type f \( $name_args \) -print -quit)
    end

    if test -n "$result"
        echo $result
        return 0
    end

    echo "Error: Docker Compose file not found." >&2
    return 1
end