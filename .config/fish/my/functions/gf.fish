function gf --description "cd to ghq-managed repo (cached ghq list)"
    type -q ghq; or return

    set -l cache ~/.cache/ghq-list

    # 初回またはキャッシュが空ならキャッシュを同期的に作成
    if not test -s $cache
        mkdir -p ~/.cache
        ghq list >$cache
    end

    # ghq root はfzf表示前に取得（選択後の遅延を回避）
    set -l root (ghq root)

    set -l repo (fzf --bind "start:unbind(enter)" --bind "load:rebind(enter)" <$cache)
    or return

    cd $root/$repo

    # tide は非同期プロンプトのため、cd 直後の1描画分だけ git 情報が
    # 移動前リポジトリのブランチ名のまま残る（PWD 部分は即時更新されるが
    # ブランチはバックグラウンド再計算が終わるまで古いまま）。
    # gf は別リポジトリへジャンプする用途なので、プロンプト変数を同期的に
    # 再計算してから制御を返し、移動直後から正しいブランチを表示させる。
    # _tide_*_line_prompt を fish_prompt の外から呼ぶと、通常 fish_prompt が
    # 用意する変数が未設定でエラーになる（例: _tide_item_character の
    # `test $_tide_status = 0`）。gf は正常終了しているので 0 を与えておく。
    # set -lx なので呼び出し先の関数からは見え、gf 終了時に自動で消える。
    if functions -q _tide_1_line_prompt
        set -lx _tide_status 0
        set -lx _tide_pipestatus 0
        set -lx _tide_jobs 0
        if contains newline $_tide_left_items
            set -U _tide_prompt_$fish_pid (_tide_2_line_prompt)
        else
            set -U _tide_prompt_$fish_pid (_tide_1_line_prompt)
        end
    end

    # 次回用にバックグラウンドでキャッシュをアトミック更新。
    # 失敗時は .tmp を残さず、stderr は .err に上書きして可視化する（追記だと無限に肥大する）。
    fish -c "if ghq list >$cache.tmp 2>$cache.err
        mv $cache.tmp $cache
    else
        rm -f $cache.tmp
    end" &
    disown
end
