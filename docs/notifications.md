# Windowsトースト通知の中身

AGENTS.md の「Windowsトースト通知（WSL2専用）」の詳細。エントリポイントと
`lib/` の分担・依存はあちらにあり、ここには**通知ごとの内容と抑止の設計**を置く。

#### 完了通知（Stopフック）

タイトルに作業中のリポジトリ名とブランチ、本文にトランスクリプトから抽出した最後のアシスタント発言（サブエージェント分は除外、1行120文字に整形）を出す。

```
✅ dotfiles (main)
テストを追加してlintも通りました。コミット済みです。
```

本文の長さは `STOP_NOTIFICATION_SUMMARY_MAX` で変えられる。トランスクリプトが読めない場合は `タスクが完了しました` にフォールバックする。

#### 日報リマインド通知

平日の業務時間中に日報の状態をチェックして通知する。`nippo-check.sh` は呼び出し元コンテキストを第1引数で受け取り、報告する内容を変える。

| チェック           | stop | cron |
| ------------------ | ---- | ---- |
| 📝 日報未作成      | ✓    | ✓    |
| 🟢 タイマー未終了  | ✓    | ✓    |
| 📊 finalize忘れ    | ✓    | ✓    |
| ⏰ 90分以上未更新  | −    | ✓    |
| 📋 未完了タスクN件 | −    | ✓    |

`stop` は応答が終わるたびに発火するので、一日中真になり続ける下2つは cron 専用にしている。加えて Stop フック側で二段のゲートを掛ける。

1. **実行ゲート** — チェック自体を10分に1回まで。日報は `/mnt/c` (9p) 上にあり1ファイル操作あたり数秒かかるため
2. **通知クールダウン** — 同じ内容の通知は60分に1回まで。内容が変われば窓の途中でも通知する

状態は `~/.cache/claude-nippo-notify/{last-run,last-notify}` に持つ。通知が来なくなったと思ったらこの2ファイルを消せばリセットされる。

セットアップ:

```fish
touch ~/.config/nippo-notify-enabled
crontab -e
# 以下を追加
# 0 9,11,13,15,17,19 * * 1-5 $HOME/scripts/nippo-cron.sh >> $HOME/.nippo-cron.log 2>&1
```

無効化は `rm ~/.config/nippo-notify-enabled`。動作確認は `scripts/test-nippo-check.sh` / `scripts/test-notify-cooldown.sh` / `scripts/test-stop-notification.sh`。
