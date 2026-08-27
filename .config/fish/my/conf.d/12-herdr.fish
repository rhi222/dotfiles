# herdr 起動ラッパー
#
# reboot 後の `he` 起動で「レイアウト + nvim + AI agent」を復元する。
# tmux の continuum(自動復元) + resurrect(@resurrect-processes で nvim 再起動) に相当。
#
# - レイアウト / タブ名 / ペイン label / cwd : herdr の session.json が復元する（native）
# - Claude / Codex                           : session hook + Herdr native agent restore
# - nvim                                     : herdr は前面プロセスを保存しないため、
#                                              nvim が自分でマーカーを残す。
#                                              nvim   -> ~/.local/state/herdr-nvim/<owner>.json
#                                                        (my/settings/herdr-registry.lua)
#                                              復元は ~/scripts/session/herdr-restore.sh が行う。
#                                              一斉起動を避けるため種別ごとに投入数と間隔を絞る。
#                                              nvim 側のバッファは auto-session がペイン単位で復元する。
#
# 復元はバックグラウンドで走らせ、TUI へのアタッチは待たない。
# 投入は数分に散るため、進み具合は `he --status` で見る（開始と完了は
# Windows トーストでも通知する）。

function he --description 'herdr 起動: native agent restore + nvim の段階復元'
    # 状態表示だけ。サーバー起動もアタッチもしない。
    # 表示の組み立ては herdr-restore.sh に寄せ、ここではパースしない。
    if contains -- --status $argv
        $HOME/scripts/session/herdr-restore.sh --status
        return
    end

    set -l state $XDG_STATE_HOME
    test -n "$state"; or set state $HOME/.local/state
    set -l lock "$state/herdr-restore.boot.lock"
    mkdir -p (dirname "$lock")

    # 複数端末から同時に `he` を実行しても、サーバー起動は1プロセスだけが行う。
    # fd 9 は begin ブロックを抜けると閉じられ、ロックも自動解放される。
    begin
        flock --exclusive 9

        # ロック取得後に再判定し、先行する `he` が起動済みなら二重起動しない。
        if not herdr session list --json 2>/dev/null | jq -e '.sessions[]? | select(.name == "default" and .running == true)' >/dev/null 2>&1
            # headless でサーバー起動 → session.json からレイアウトを復元
            # バックグラウンドサーバーにはロック用 fd を継承させない。
            # disown でジョブテーブルから外し、呼び出し元シェルの exit を妨げないようにする。
            setsid herdr server 9>&- >/dev/null 2>&1 &
            disown

            # API が応答する（= 復元完了）まで待つ。
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
            end
        end

        # serverが別経路ですでに起動していてもnvim復元は必要。driver側が
        # idle paneだけへ絞り、flockで二重投入を防ぐ。
        if herdr workspace list >/dev/null 2>&1
            setsid $HOME/scripts/session/herdr-restore.sh 9>&- >/dev/null 2>&1 &
            disown
        end
    end 9>"$lock"

    # TUI をアタッチ（既存サーバーにも接続する）
    herdr
end
