function gf --description "cd to ghq-managed repo (cached ghq list)"
    type -q ghq; or return

    set -l cache (__ghq_list_cache_path)

    # 初回またはキャッシュが空ならキャッシュを同期的に作成
    if not test -s $cache
        __ghq_list_cache_refresh
    end

    # ghq root はfzf表示前に取得（選択後の遅延を回避）
    set -l root (ghq root)

    # 次回用のキャッシュ更新は fzf を出す「前」に投げる。
    # 以前は cd の後に投げていたが、fzf を ESC でキャンセルすると下の
    # `or return` で抜けてしまい更新が走らなかった。そのため
    # 「ghq get → gf に出ない → ESC → もう一度 gf」を繰り返しても永久に
    # 反映されず、一度どこかのリポジトリへ cd するまで直らなかった。
    # fzf は下でこのファイルを開いてから読むので、更新の mv（アトミックな
    # rename）が途中で走っても fzf 側は古い inode を読み切る。
    __ghq_list_cache_refresh >/dev/null 2>&1 &
    disown

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
end
