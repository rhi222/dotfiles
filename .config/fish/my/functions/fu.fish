# followup の一覧を開く（cron が毎時書き換える）
#
#   fu    # 最新の一覧をページャで開く
function fu --description 'followup の一覧を開く'
    set -l dir (set -q FOLLOWUP_STATE_DIR; and echo $FOLLOWUP_STATE_DIR; or echo $HOME/.local/state/followup)
    set -l file $dir/latest.md
    if not test -f $file
        echo "まだ一覧がありません: $file" >&2
        return 1
    end
    if type -q bat
        bat --style=plain --language=markdown $file
    else
        less $file
    end
end
