function ftmux --description "Fuzzy switch tmux window/session (works outside tmux too; pretty list; plain fzf)"
    if not type -q tmux
        echo "ftmux: tmux not found" >&2
        return 1
    end
    if not type -q fzf
        echo "ftmux: fzf not found" >&2
        return 1
    end

    # tab delimiter (safe)
    set -l TAB (printf '\t')

    set -l mode $argv[1]
    if test -z "$mode"
        set mode win
    end

    # Ensure at least one session exists
    if not tmux has-session 2>/dev/null
        tmux new-session -d -s main
    end

    # -------------------------
    # OUTSIDE tmux
    # -------------------------
    if not set -q TMUX
        set -l line (
            tmux list-sessions -F "#{session_name}$TAB#{session_windows}$TAB#{?session_attached,attached,}$TAB#{session_created_string}" \
            | awk 'BEGIN{FS="\t"; OFS="\t"} {
                s=$1; w=$2; a=$3; c=$4;
                if (a == "") a="-";
                printf "%s\t%s [%s windows] %s  %s\n", s, s, w, a, c
              }' \
            | fzf --prompt="tmux attach> " --delimiter="$TAB" --with-nth=2 --exit-0
        )
        if test -z "$line"
            return 0
        end

        set -l parts (string split $TAB -- $line)
        set -l name $parts[1]
        exec tmux attach -t "$name"
    end

    # -------------------------
    # INSIDE tmux
    # -------------------------
    switch $mode
        case w win window
            set -l line (
                tmux list-windows -F "#{window_index}$TAB#{window_name}$TAB#{window_panes}$TAB#{pane_current_path}$TAB#{?window_active,*, }$TAB#{?window_last_flag,L, }" \
                | awk 'BEGIN{FS="\t"; OFS="\t"} {
                    idx=$1; name=$2; panes=$3; cwd=$4; act=$5; last=$6;
                    flags="";
                    if (act == "*") flags=flags "*";
                    if (last == "L") flags=flags "L";
                    if (flags != "") flags=" (" flags ")";
                    printf "%s\t[%s panes] %s — %s%s\n", idx, panes, name, cwd, flags
                  }' \
                | fzf --prompt="tmux window> " --delimiter="$TAB" --with-nth=2 --exit-0
            )
            if test -z "$line"
                return 0
            end

            set -l parts (string split $TAB -- $line)
            set -l idx $parts[1]
            tmux select-window -t "$idx"

        case s session sessions
            set -l line (
                tmux list-sessions -F "#{session_name}$TAB#{session_windows}$TAB#{?session_attached,attached,}$TAB#{session_created_string}" \
                | awk 'BEGIN{FS="\t"; OFS="\t"} {
                    s=$1; w=$2; a=$3; c=$4;
                    if (a == "") a="-";
                    printf "%s\t%s [%s windows] %s  %s\n", s, s, w, a, c
                  }' \
                | fzf --prompt="tmux session> " --delimiter="$TAB" --with-nth=2 --exit-0
            )
            if test -z "$line"
                return 0
            end

            set -l parts (string split $TAB -- $line)
            set -l name $parts[1]
            tmux switch-client -t "$name"

        case p pane panes
            set -l line (
                tmux list-panes -a -F "#{pane_id}$TAB#{session_name}$TAB#{window_index}:#{window_name}$TAB#{pane_index}$TAB#{pane_current_path}$TAB#{pane_current_command}" \
                | awk 'BEGIN{FS="\t"; OFS="\t"} {
                    pid=$1; s=$2; w=$3; p=$4; cwd=$5; cmd=$6;
                    printf "%s\t%s/%s (pane %s) — %s [%s]\n", pid, s, w, p, cwd, cmd
                  }' \
                | fzf --prompt="tmux pane> " --delimiter="$TAB" --with-nth=2 --exit-0
            )
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
