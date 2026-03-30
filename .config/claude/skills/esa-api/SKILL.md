---
name: esa-api
description: esa.io APIアクセスの共通ナレッジ。esa APIを叩く必要がある場合に参照する。「esa」「esaの記事」「esaのリビジョン」「esaに投稿」等で使用。
---

# esa API スキル

esa.io の API を Bash ツールの `curl` + `jq` で叩くための共通ナレッジ。

## 認証

```bash
# ESA_ACCESS_TOKEN 環境変数を使用
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts"
```

- `ESA_ACCESS_TOKEN` 環境変数が必須（設定済み）
- トークン未設定時は処理前にエラーを出すこと

## チーム

2つのチームがある:
- `forcia`
- `forcia-engineers`

利用時は引数やコンテキストでチーム名を特定すること。

## URL体系

| 用途 | URL |
|------|-----|
| APIベース | `https://api.esa.io/v1/teams/${ESA_TEAM}` |
| Webベース | `https://${ESA_TEAM}.esa.io` |

## 主要エンドポイント

### 記事一覧・検索

```bash
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts?q=${QUERY}&page=1&per_page=100"
```

レスポンス: `{ "posts": [...], "total_count": N, "next_page": N|null }`

### 記事取得

```bash
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts/${POST_NUMBER}"
```

### リビジョン一覧

```bash
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts/${POST_NUMBER}/revisions?page=1&per_page=100"
```

レスポンス: `{ "revisions": [...], "total_count": N, "next_page": N|null }`

各リビジョン:
```json
{
  "number": 25,
  "created_at": "2026-03-27T14:38:32+09:00",
  "body_md": "...",
  "body_html": "..."
}
```

- 降順（新しい順）で返る
- `created_at` は `+09:00` タイムゾーン付き ISO 8601

### リビジョン比較（diff）

```bash
curl -sf \
  -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
  "https://api.esa.io/v1/teams/${ESA_TEAM}/posts/${POST_NUMBER}/revisions/compare/${FROM}...${TO}"
```

- `FROM`, `TO` はリビジョン番号
- 3ドット (`...`) で区切る

## ブラウザURL

### 記事

```
https://${ESA_TEAM}.esa.io/posts/${POST_NUMBER}
```

### リビジョン比較（HTML diff）

```
https://${ESA_TEAM}.esa.io/posts/${POST_NUMBER}/revisions/compare/${FROM}...${TO}/html_diff
```

## ページネーション

- `page` パラメータ（1始まり）
- `per_page` パラメータ（最大100）
- レスポンスの `next_page` が `null` になるまでループ

```bash
page=1
all_items='[]'
while true; do
  response=$(curl -sf \
    -H "Authorization: Bearer ${ESA_ACCESS_TOKEN}" \
    "${API_URL}?page=${page}&per_page=100")
  items=$(echo "$response" | jq '.revisions // .posts')
  all_items=$(echo "$all_items" "$items" | jq -s 'add')
  next_page=$(echo "$response" | jq -r '.next_page')
  [[ "$next_page" == "null" ]] && break
  page="$next_page"
done
```

## エラーハンドリング

- `curl -sf` を使用（エラー時は非ゼロ終了、レスポンスボディ非表示）
- `ESA_ACCESS_TOKEN` 未設定チェックを最初に行う
- `jq` 存在チェックも行う
