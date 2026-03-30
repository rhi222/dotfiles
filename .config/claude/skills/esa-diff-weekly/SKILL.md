# esa 週次差分URL取得 & サマリ

指定した esa 投稿の直近一週間のリビジョン差分を取得し、compare URL を表示してサマリする。

引数: $ARGUMENTS
形式: `<team_name> <post_number>` (例: `forcia-engineers 14491`)

## 参照スキル

`.config/claude/skills/esa-api/SKILL.md` の esa API ナレッジに従ってAPIを叩くこと。

## 手順

### 1. 引数パース

`$ARGUMENTS` からチーム名と投稿番号を取得する。

### 2. 事前チェック

Bash で以下を確認:
- `ESA_ACCESS_TOKEN` 環境変数が設定されているか
- `jq` コマンドが利用可能か

### 3. リビジョン一覧取得

Bash で esa API のリビジョン一覧エンドポイントを叩く:

```bash
ESA_TEAM="<team_name>"
POST_NUMBER="<post_number>"

curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts/${POST_NUMBER}/revisions?page=1&per_page=100" \
  | jq '.revisions | map({number, created_at})'
```

ページネーションがある場合は `next_page` を確認してループする。

### 4. 直近7日間のフィルタ

取得したリビジョンから、`created_at` が直近7日間以内のものを抽出する。
jq でフィルタ:

```bash
CUTOFF=$(date -d "7 days ago" --iso-8601=seconds)
echo "$revisions" | jq --arg cutoff "$CUTOFF" '
  map(select(.created_at >= $cutoff))
'
```

### 5. compare URL 生成

フィルタしたリビジョンの最小番号(from)と最大番号(to)を取得し、URLを生成:

```
https://<team_name>.esa.io/posts/<post_number>/revisions/compare/<from>...<to>/html_diff
```

**このURLをユーザーに表示すること（必須）。**

### 6. diff 内容取得（サマリ用）

compare API を叩いてdiff内容を取得:

```bash
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts/${POST_NUMBER}/revisions/compare/${FROM}...${TO}" \
  | jq '{body_md: .body_md, diff_body_md: .diff_body_md}'
```

### 7. サマリ

取得したdiff内容を以下の観点でサマリする:
- 主な変更点（追加・削除・修正）
- 変更の意図（推測）
- 影響範囲

## エラー時

- リビジョンが直近7日間にない場合: 「過去7日間のリビジョンがありません」と報告
- リビジョンが1つしかない場合: diffではなくそのリビジョンの内容をサマリ
- API エラー時: ステータスコードとエラー内容を報告
