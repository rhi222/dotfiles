# Fish history settings

# historyサイズ制限を拡大
set -g fish_history_max 100000

# 重複するコマンドを履歴に保存しない
set -g fish_history_ignore_duplicates 1

# 先頭にスペースがあるコマンドを履歴に保存しない（秘密情報入力時に便利）
set -g fish_history_ignore_space 1

# 複数セッション間でのhistory共有を有効化（パフォーマンス最適化）
function __fish_shared_history --on-event fish_prompt
    # 過度な頻度での実行を避けるため、10コマンドに1回実行
    if test (math (random) % 10) -eq 0
        history --save 2>/dev/null
        history --merge 2>/dev/null
    end
end