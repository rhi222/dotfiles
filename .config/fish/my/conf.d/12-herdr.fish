# herdr 起動ラッパー
#
# reboot 後の `he` 起動で「レイアウト + AI エージェント + nvim」を復元する。
# tmux の continuum(自動復元) + resurrect(@resurrect-processes で nvim 再起動) に相当。
#
# - レイアウト / タブ名 / ペイン label / cwd : herdr の session.json が復元する（native）
# - AI エージェント(claude/codex 等)         : herdr の resume_agents_on_restore が復元する（native）
#   ※ claude の resume には SessionStart hook が必要。settings.json の
#     `bash "$HOME/.claude/hooks/herdr-agent-state.sh" session` が正しく動くこと。
# - nvim                                     : herdr は非エージェントのプロセスを復元しないため、
#                                              このラッパーが補う。どのペインで nvim が動いていたかは
#                                              nvim 側が自動で ~/.local/state/herdr-nvim/<pane_id> に
#                                              マーカーを残す（nvim の autocmd。手動ラベル付けは不要）。
#                                              nvim 側の auto-session がファイル/バッファを復元する。

function he --description 'herdr 起動: コールドスタート時に nvim を動かしていたペインで nvim を自動復元'
    set -l reg $XDG_STATE_HOME/herdr-nvim
    test -n "$XDG_STATE_HOME"; or set reg $HOME/.local/state/herdr-nvim
    set -l lock "$reg.lock"
    mkdir -p (dirname "$lock")

    # 複数端末から同時に `he` を実行しても、コールドスタート復元は1プロセスだけが行う。
    # fd 9 は begin ブロックを抜けると閉じられ、ロックも自動解放される。
    begin
        flock --exclusive 9

        # ロック取得後に再判定し、先行する `he` が起動済みなら二重復元しない。
        if not herdr session list --json 2>/dev/null | jq -e '.sessions[]? | select(.name == "default" and .running == true)' >/dev/null 2>&1
            # headless でサーバー起動 → session.json からレイアウト/AI エージェントを復元
            # バックグラウンドサーバーにはロック用 fd を継承させない。
            # disown でジョブテーブルから外し、呼び出し元シェルの exit を妨げないようにする。
            setsid herdr server 9>&- >/dev/null 2>&1 &
            disown

            # API が応答する（= 復元完了）まで待つ。失敗時はマーカーを保持する。
            # 起動が遅い環境でも取りこぼさないよう、タイムアウトは長めに取る
            # （応答すれば即 break するので、待ち時間が伸びるのは失敗時のみ）。
            set -l ready false
            for i in (seq 1 120)
                if herdr workspace list >/dev/null 2>&1
                    set ready true
                    break
                end
                sleep 0.25
            end

            if $ready
                # 復元直後のシェル初期化を少し待つ
                sleep 1

                if test -d "$reg"
                    # 全ペイン一覧を正常に取得できた場合だけ、復元と古いマーカーの掃除を行う。
                    # 一時的な API/jq エラーを「ペインが存在しない」と誤判定しないため。
                    set -l alive
                    set -l inventory_ok true
                    set -l workspace_json (herdr workspace list 2>/dev/null)
                    if test $status -ne 0; or not printf '%s\n' "$workspace_json" | jq -e '.result.workspaces | type == "array"' >/dev/null 2>&1
                        set inventory_ok false
                    end

                    if $inventory_ok
                        for ws in (printf '%s\n' "$workspace_json" | jq -r '.result.workspaces[]?.workspace_id')
                            set -l pane_json (herdr pane list --workspace "$ws" 2>/dev/null)
                            if test $status -ne 0; or not printf '%s\n' "$pane_json" | jq -e '.result.panes | type == "array"' >/dev/null 2>&1
                                set inventory_ok false
                                break
                            end
                            set -a alive (printf '%s\n' "$pane_json" | jq -r '.result.panes[]?.pane_id')
                        end
                    end

                    if $inventory_ok
                        for f in $reg/*
                            test -e "$f"; or continue
                            set -l pane (basename "$f")
                            if contains -- "$pane" $alive
                                herdr pane run "$pane" nvim
                            else
                                rm -f "$f"
                            end
                        end
                    end
                end
            end
        end
    end 9>"$lock"

    # TUI をアタッチ（既存サーバーにも接続する）
    herdr
end
