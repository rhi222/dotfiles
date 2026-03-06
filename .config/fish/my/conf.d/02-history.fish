# Fish history settings
#
# fishのhistoryは以下がデフォルト動作として組み込まれている:
# - 重複コマンドの自動除外
# - スペース先頭コマンドの非保存
# - 最大保存数は262,144件（ハードコード、変更不可）
# そのため、これらに対応する設定変数は存在しない。

# 複数セッション間でのhistory共有を有効化（パフォーマンス最適化）
function __fish_shared_history --on-event fish_prompt
    # 過度な頻度での実行を避けるため、10コマンドに1回実行
    if test (math (random) % 10) -eq 0
        history --save 2>/dev/null
        history --merge 2>/dev/null
    end
end
