---
name: followup
description: Slackで人に投げて返事を待っている件と、Slackのメンション・DMやJiraで自分が頼まれている件を集め、前回から変わったものに🆕を付けて一覧にする。「あれどうなった」「返事来てる？」「頼まれ事の一覧」「followup」などで使用。cronから毎時ヘッドレスで呼ばれる。Slack・Jiraへは書き込まない。
allowed-tools: Bash(dotctl:*), mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Slack__slack_read_thread, mcp__claude_ai_Slack__slack_read_user_profile, mcp__claude_ai_Atlassian__getAccessibleAtlassianResources, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
---

# followup

作業中に「あれどうなった」と気が散らないよう、返事待ちと頼まれ事を毎時まとめる。
**判断（何が返事待ちか）だけをここで行い、差分・一覧・通知は `dotctl followup apply` に任せる。**

**Slack・Jiraへは一切書き込まない。** 書き込めるtoolはこのskillに許可されていない。

## 1. 自分を特定する

`mcp__claude_ai_Slack__slack_read_user_profile` を引数なしで呼び、自分のuser IDを控える。
以後の検索は「今日を含めて直近7日」に絞る（`after:` には8日前の日付を入れる）。

## 2. 返事待ちを集める（kind: waiting）

1. `from:<@自分のID> after:<8日前>` で自分の発言を検索する。全ページ取り切る
2. 次のどちらかに当たる発言だけを候補にする
   - 特定の人をメンションした質問・依頼
   - DMでの質問・依頼
     雑談、報告、お礼、自分宛てのメモは候補にしない。迷ったら候補にしない
3. 候補ごとに `slack_read_thread` でスレを読み、自分の発言より後に、相手（メンション先・DM相手）の発言があるかを見る
   - あれば `replied: true`。`reply_at` は相手の最初の返信の時刻、`reply_summary` はその冒頭30字
   - なければ `replied: false`

## 3. 頼まれ事を集める（kind: asked）

**Slack**：`<@自分のID> after:<8日前>` と、DMで自分宛てに来た発言を検索する。
スレを読み、その発言より後に自分が同じスレで発言していないものだけを残す。

**Jira**：`getAccessibleAtlassianResources` でcloudIdを取り、次のJQLで検索する。

```
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

`fields` は `["summary", "updated", "created"]`。`since` は `created`、`updated_at` は `updated`。

## 4. dotctlへ渡す

集めた件を次の形のJSONにし、heredocで渡す。

- `key`：Slackは `slack:<channel_id>/<message_ts>`（返事待ちは自分の発言、頼まれ事は相手の発言）、Jiraは `jira:<課題キー>`
- `where`：Slackはチャンネル名（`#name`）かDMなら `DM`、Jiraは `Jira`
- `who`：相手の表示名。Jiraは空
- `summary`：元の発言の冒頭30字。Jiraは `<課題キー> <summary>`
- `since`：元の発言の時刻（ISO 8601、タイムゾーン付き）
- `generated_at`：今の時刻

```bash
dotctl followup apply --in - <<'JSON'
{"generated_at":"2026-10-08T13:00:00+09:00","items":[
{"key":"slack:C123/1786335015.733309","kind":"waiting","source":"slack","where":"#ch-x","who":"Aさん","summary":"〜の件どうでしょう","url":"https://example.slack.com/archives/C123/p1786335015733309","since":"2026-10-07T10:00:00+09:00","replied":true,"reply_at":"2026-10-08T11:20:00+09:00","reply_summary":"確認しました"},
{"key":"jira:PROJ-123","kind":"asked","source":"jira","where":"Jira","who":"","summary":"PROJ-123 〜","url":"https://example.atlassian.net/browse/PROJ-123","since":"2026-10-06T09:00:00+09:00","updated_at":"2026-10-08T09:00:00+09:00"}
]}
JSON
```

0件でも `"items":[]` で渡す（一覧を「なし」に更新するため）。
**検索やスレの読み取りが途中で失敗したら、dotctlを呼ばずに終える。** 欠けた結果で前回状態を上書きすると、まだ返事が無い件が消えたり、次回に全件が🆕になったりする。

## 5. 報告する

dotctlのstdout（一覧mdのpathと、あれば通知文）をそのまま返す。
対話で呼ばれたときは、一覧mdの中身も表示する。
