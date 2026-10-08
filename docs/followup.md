# followup：Linearに貼ったSlackスレの動き

作業中に「あれどうなった」と気が散るのを止めるため、自分がボールを持ったSlackスレの動きを平日3回まとめる。
「次の定時に必ず分かる」状態にして、気になっても作業へ戻れるようにする。

## 何を追うか

Linearの未完了issue（completed・canceled・duplicate以外。stateは問わない）の本文にあるSlackのURL。
スタンプで起票したissueには元スレのpermalinkが入るので、追うための印を新たに付ける必要は無い。

- Laterに入れただけのスレは追わない。「見ただけ・任せたい」をボールにしないため
- stateで絞らない。Waitingへの変え忘れで漏れるのを避ける
- Jiraは追わない

### v1をやめた理由

v1はSlackを全文検索し、返事待ち・頼まれ事をAIに判定させた。
実測で1回600秒超・約$8、検索36回・約600件となり、定時実行には重すぎた（2026-10-07）。
入口をLinearに限ると検索が要らず、読む本数が未完了issueの数で頭打ちになる（実測31本、2026-10-08）。

## 分担

| 層       | 場所                                                       | 役割                                                       |
| -------- | ---------------------------------------------------------- | ---------------------------------------------------------- |
| 対象抽出 | `scripts/followup/targets.sh`（`dotctl followup targets`） | Linearからスレを取り出し、前回の最新tsを `oldest` に付ける |
| 読み取り | `.config/claude/skills/followup/`                          | 各スレの最後の発言を書き写す。判断しない                   |
| 状態     | `internal/followup/`（`dotctl followup apply`）            | 前回との差分で🆕を判定し、一覧mdと通知文を書く             |
| 起動     | `scripts/followup/digest-cron.sh`                          | 平日3回、Haikuで動かす。🆕があればtoastを出す              |
| 閲覧     | fish関数 `fu`                                              | 一覧mdを開く                                               |

**Slackへは書き込まない。** cronの `--allowedTools` はスレの読み取り・自分のprofile・dotctlだけで、
`tests/followup/test-digest-cron.sh` が許可リストを検証する。

## 読む量を抑える仕組み

`slack_read_thread` の `oldest` は排他的で、渡したtsより新しい返信だけが返る（親は常に返る）。
前回の最新tsを渡すので、動きの無いスレは親1件分しか読まない。

`response_format: concise` はtsと発言者IDを出さないので使えない。

## 🆕の付き方

- 前回から最新発言のtsが進み、その発言者が自分以外
- 初回（状態ファイルが無い）と、新しく増えたスレは🆕にしない
- 一覧は「自分の番」（最後の発言者が自分以外）と「相手待ち」（自分）に分ける

toastは🆕が1件以上のときだけ出る。

## 状態

`~/.local/state/followup/`（`FOLLOWUP_STATE_DIR` で変更可）。

| ファイル       | 中身                                          |
| -------------- | --------------------------------------------- |
| `targets.json` | 今回追うスレとissue。`targets` が毎回書き直す |
| `state.json`   | スレごとの最新発言。消すと次回は初回扱い      |
| `latest.md`    | 一覧。毎回丸ごと書き直す                      |
| `notice`       | toastの本文。cronがtoastを出したあとに消す    |

`apply` は `targets.json` の全スレが揃わない入力を拒否し、何も書かない。
Linearの取得に失敗したときは `targets.json` を書き換えず、claudeも呼ばない。

## 有効化と確認

    touch ~/.config/followup-enabled
    FOLLOWUP_DRY_RUN=1 FOLLOWUP_FORCE=1 bash scripts/followup/digest-cron.sh

crontabの行は [bootstrap.md](bootstrap.md)。
