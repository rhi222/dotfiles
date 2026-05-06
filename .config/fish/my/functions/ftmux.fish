function ftmux --description "Fuzzy switch tmux window/session (works outside tmux too; pretty list; plain fzf)"
    if not type -q tmux
        echo "ftmux: tmux not found" >&2
        return 1
    end
    if not type -q fzf
        echo "ftmux: fzf not found" >&2
        return 1
    end

    set -l TAB (printf '\t')

    set -l mode $argv[1]
    if test -z "$mode"
        set mode win
    end

    if not tmux has-session 2>/dev/null
        tmux new-session -d -s main
    end

    # 共通: 整形済み入力(ID\t表示文字列)から fzf で選び、ID列を返す
    function __ftmux_pick_id --argument-names prompt --no-scope-shadowing
        set -l line (fzf --prompt="$prompt" --delimiter="$TAB" --with-nth=2 --exit-0)
        if test -z "$line"
            return 1
        end
        set -l parts (string split $TAB -- $line)
        echo $parts[1]
    end

    # セッション一覧の awk フォーマッタ（attach前/後で使い回す）
    set -l session_fmt 'BEGIN{FS="\t"; OFS="\t"} {
        s=$1; w=$2; a=$3; c=$4;
        if (a == "") a="-";
        printf "%s\t%s [%s windows] %s  %s\n", s, s, w, a, c
      }'

    # OUTSIDE tmux: セッションを選んで attach
    if not set -q TMUX
        set -l name (tmux list-sessions \
            -F "#{session_name}$TAB#{session_windows}$TAB#{?session_attached,attached,}$TAB#{session_created_string}" \
            | awk $session_fmt \
            | __ftmux_pick_id "tmux attach> ")
        or return 0
        exec tmux attach -t "$name"
    end

    # INSIDE tmux
    switch $mode
        case w win window
            set -l idx (tmux list-windows \
                -F "#{window_index}$TAB#{window_name}$TAB#{window_panes}$TAB#{pane_current_path}$TAB#{?window_active,*, }$TAB#{?window_last_flag,L, }" \
                | awk 'BEGIN{FS="\t"; OFS="\t"} {
                    idx=$1; name=$2; panes=$3; cwd=$4; act=$5; last=$6;
                    flags="";
                    if (act == "*") flags=flags "*";
                    if (last == "L") flags=flags "L";
                    if (flags != "") flags=" (" flags ")";
                    printf "%s\t[%s panes] %s — %s%s\n", idx, panes, name, cwd, flags
                  }' \
                | __ftmux_pick_id "tmux window> ")
            or return 0
            tmux select-window -t "$idx"

        case s session sessions
            set -l name (tmux list-sessions \
                -F "#{session_name}$TAB#{session_windows}$TAB#{?session_attached,attached,}$TAB#{session_created_string}" \
                | awk $session_fmt \
                | __ftmux_pick_id "tmux session> ")
            or return 0
            tmux switch-client -t "$name"

        case p pane panes
            set -l line (tmux list-panes -a \
                -F "#{pane_id}$TAB#{session_name}$TAB#{window_index}:#{window_name}$TAB#{pane_index}$TAB#{pane_current_path}$TAB#{pane_current_command}" \
                | awk 'BEGIN{FS="\t"; OFS="\t"} {
                    pid=$1; s=$2; w=$3; p=$4; cwd=$5; cmd=$6;
                    printf "%s\t%s\t%s/%s (pane %s) — %s [%s]\n", pid, s, s, w, p, cwd, cmd
                  }' \
                | fzf --prompt="tmux pane> " --delimiter="$TAB" --with-nth=3 --exit-0)
            if test -z "$line"
                return 0
            end
            set -l parts (string split $TAB -- $line)
            set -l pane_id $parts[1]
            set -l sess $parts[2]
            tmux switch-client -t "$sess"
            tmux select-pane -t "$pane_id"

        case '*'
            echo "Usage: ftmux [win|session|pane]" >&2
            return 1
    end
end
