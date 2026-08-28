# Codexの確認質問に答える

`/nippo-add こたえ: NSY-12` で呼ばれる。EMレーンが `My Review` に置いた
確認質問に回答し、回答を織り込ませるためにissueを `AI Queued` へ戻す。

## 1. 質問を読む

`em-dispatch.sh` が出力JSONを状態ディレクトリに残しているので、Linearの
コメントを解析せずこれを読む。

```bash
STATE_DIR="${LINEAR_EM_STATE_DIR:-$HOME/.local/state/linear-em-dispatch}"
cat "$STATE_DIR/NSY-12.json" | jq '{draft_path, summary, questions}'
```

ファイルが無い場合は、Linearのissueコメントから「Codex叩き台完了」で始まる
最新のものを読んで代替する。それも無ければ、質問が見つからない旨を伝えて終了する。

## 2. 回答を取る

`AskUserQuestion` で1問ずつではなく**まとめて**提示する（最大4問。5問目がある場合は
2回に分ける）。`options` をそのまま選択肢にする。`multiSelect` は使わない。

`header` には `Q1` `Q2` のような短いラベルを使う。

## 3. 回答をLinearへ残す

```bash
source "$(ghq root)/github.com/rhi222/dotfiles/scripts/lib/linear-api.sh"
linear_comment "<issueId>" "$(cat <<'EOF'
西山の回答

1. 境界をどこで切りますか → 責任主体を軸にする
2. 誰に最初に見せますか → matsushitaさんと具体化してから予約チーム
3. 拡張を残しますか → 暫定で残す
EOF
)"
```

issueId は状態ディレクトリのJSONには無いので、`linear_issues_in_state "My Review"`
から identifier で引く。

## 4. 再投入する

```bash
bash "$(ghq root)/github.com/rhi222/dotfiles/scripts/linear/em-dispatch.sh" \
  enqueue NSY-12
```

`em_find_issue` は `My Review` も探索対象に含めるので、state を手で戻す必要はない。
`enqueue` が `My Review` から直接 `AI Queued` へ移す。

## 5. 2周目の引き継ぎ

Codexは1周目の叩き台ファイルを読み直して仕上げる。`codex exec resume` は使わない。
セッションの永続に依存すると、状態ディレクトリを消したときや別マシンから
動かしたときに壊れるため。

叩き台ファイルとLinearコメントの両方が残っているので、プロンプトに書かれた
「先に読むもの」と `01_Inbox/ai/` の既存ファイルから2周目の文脈は再構成できる。

## 日報への記録

作業ログに1行残す。

```markdown
- HH:MM Codexの確認質問に回答（NSY-12・3問）→ AI Queued へ再投入
```
