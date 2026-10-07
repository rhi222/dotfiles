# followup：返事待ちと頼まれ事のまとめ

作業中に「あれどうなった」と気が散るのを止めるため、返事待ちと頼まれ事を毎時まとめる。
「次の定時に必ず分かる」状態にして、気になっても作業へ戻れるようにする。

## 何を拾うか

- **返事待ち**：直近7日に自分がSlackで特定の人へ投げた質問・依頼（メンション付き、またはDM）
- **頼まれ事**：直近7日のSlackの自分宛てメンション・DMで、自分がまだ返していないもの。Jiraで自分にアサインされた未完了の課題

返事待ちかどうかの判定はAIが行うので、誤検出・取りこぼしはある。

## 分担

| 層    | 場所                                            | 役割                                           |
| ----- | ----------------------------------------------- | ---------------------------------------------- |
| skill | `.config/claude/skills/followup/`               | Slack・Jiraを読み、各件を分類してJSONにする    |
| 状態  | `internal/followup/`（`dotctl followup apply`） | 前回との差分で🆕を判定し、一覧mdと通知文を書く |
| 起動  | `scripts/followup/digest-cron.sh`               | 平日9〜18時の毎時。🆕があればtoastを出す       |
| 閲覧  | fish関数 `fu`                                   | 一覧mdを開く                                   |

**Slack・Jiraへは書き込まない。** cronの `--allowedTools` に読み取り系だけを入れて担保し、
`tests/followup/test-digest-cron.sh` が許可リストを検証する。

## 🆕の付き方

- 返事待ちに相手の返信が来た
- 頼まれ事が新しく現れた、またはJiraの課題が更新された
- 初回（状態ファイルが無い）は何も🆕にしない。有効化直後に全件toastが出るのを防ぐ

toastは🆕が1件以上のときだけ出る。

## 状態

`~/.local/state/followup/`（`FOLLOWUP_STATE_DIR` で変更可）。

| ファイル     | 中身                                       |
| ------------ | ------------------------------------------ |
| `state.json` | 件ごとの前回の版。消すと次回は初回扱い     |
| `latest.md`  | 一覧。毎回丸ごと書き直す                   |
| `notice`     | toastの本文。cronがtoastを出したあとに消す |

skillの読み取りが途中で失敗したときは、dotctlを呼ばずに終わる。
欠けた結果で前回状態を上書きしないため。

## 有効化と確認

    touch ~/.config/followup-enabled
    FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash scripts/followup/digest-cron.sh

crontabの行は [bootstrap.md](bootstrap.md)。
毎時はheadlessのClaudeを1日10回動かす。使用量が気になったらcron行の時刻を減らす。
