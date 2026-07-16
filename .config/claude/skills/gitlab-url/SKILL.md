---
name: gitlab-url
description: GitLabのURL（http://gitlab.fdev/... 等）を渡されて、その先のリソース（issue、MR、ファイル、パイプライン、コミット等）を読み取り・書き込みしたいときに使う。「このMRを見て」「このissueにコメントして」「gitlab.fdevのURLの内容を教えて」「glabで操作して」等で使用。
---

# gitlab-url

GitLab の URL を `glab` CLI に変換して、URL 先のリソースを読み書きするためのリファレンス。

## 前提・環境の注意

- glab は snap でインストールされている（`/snap/bin/glab`）。**サンドボックス内では `cannot preserve mount namespace` エラーで失敗する**ため、失敗したらサンドボックスなしで再実行する。
- デフォルトホストは `gitlab.com`。**リポジトリ外から叩くときは必ずホストを指定する**：
  - サブコマンド系: `-R <host>/<group>/<project>`（例: `-R gitlab.fdev/webconnect/taco`）
  - `glab api`: `GITLAB_HOST=<host>` 環境変数（例: `GITLAB_HOST=gitlab.fdev glab api ...`）
- 認証確認は `glab auth status --hostname <host>`。**`-h` は help になるので使わない。**
- `gitlab.fdev` は認証設定済み（`api_protocol: http`）。認証切れ（401）のときは `glab auth login --hostname <host>` の実行をユーザーに依頼する。

## URL の解釈

GitLab の URL 構造:

```
http://<host>/<group>/<project>/-/<type>/<rest>
```

- `/-/` より前が **project フルパス**（group は複数階層になりうる: `a/b/c/project`）
- `/-/` より後がリソースタイプと識別子
- `/-/` が無い URL は group か project か曖昧。`glab api "projects/<enc>"` が 404 なら `glab api "groups/<enc>"` を試す
- `<enc>` = project フルパスの URL エンコード（`/` → `%2F`。例: `webconnect%2Ftaco`）

## URL タイプ → コマンド対応表（読み取り）

`REPO="-R <host>/<group>/<project>"`、`glab api` は `GITLAB_HOST=<host>` 前提。

| URL パターン | コマンド |
|---|---|
| `/-/issues/<n>` | `glab issue view <n> $REPO`（`--comments` でコメントも） |
| `/-/merge_requests/<n>` | `glab mr view <n> $REPO`（`--comments` でコメントも） |
| `/-/merge_requests/<n>/diffs` | `glab mr diff <n> $REPO` |
| `/-/blob/<ref>/<file>` | `glab api "projects/<enc>/repository/files/<enc_file>/raw?ref=<ref>"`（`<enc_file>` もパス全体をエンコード） |
| `/-/tree/<ref>/<dir>` | `glab api "projects/<enc>/repository/tree?ref=<ref>&path=<dir>&per_page=100"` |
| `/-/commit/<sha>` | `glab api "projects/<enc>/repository/commits/<sha>"`（差分は `.../commits/<sha>/diff`） |
| `/-/pipelines/<n>` | `glab api "projects/<enc>/pipelines/<n>"`（ジョブ一覧は `.../pipelines/<n>/jobs`） |
| `/-/jobs/<n>` | `glab api "projects/<enc>/jobs/<n>/trace"`（ログ取得） |
| リポジトリルート | `glab repo view $REPO` |
| issue 一覧 `/-/issues` | `glab issue list $REPO` |
| MR 一覧 `/-/merge_requests` | `glab mr list $REPO` |

検証済みの実例:

```bash
glab mr list -R gitlab.fdev/webconnect/taco
GITLAB_HOST=gitlab.fdev glab api "projects/webconnect%2Ftaco"
```

## 書き込み操作

**書き込み前に、対象 URL と送信内容をユーザーに提示して確認を取ること。**

| やりたいこと | コマンド |
|---|---|
| issue にコメント | `glab issue note <n> -m "<body>" $REPO` |
| MR にコメント | `glab mr note <n> -m "<body>" $REPO` |
| issue の更新（タイトル・ラベル等） | `glab issue update <n> ... $REPO` |
| MR の更新 | `glab mr update <n> ... $REPO` |
| issue 作成 | `glab issue create --title "..." --description "..." $REPO` |
| その他 | `glab api -X POST/PUT "projects/<enc>/..." -f key=value` |

注意:

- ラベルを付けるときは実在するラベルだけを表記そのままで使う（存在しない名前を渡すと **エラーにならず新規作成されてしまう**）。一覧は `glab api "projects/<enc>/labels?per_page=100"` で取得する
- MR 作成はリポジトリ固有の慣習（テンプレート・ラベル運用）があるため、対象リポジトリに `create-mr` 等の専用スキルがあればそちらを優先する

## 汎用フォールバック

対応表にないリソース（wiki、release、snippet 等）は GitLab REST API v4 を `glab api` で直接叩く:

```bash
GITLAB_HOST=<host> glab api "projects/<enc>/<endpoint>"
```

- ページネーションは `?page=N&per_page=100`。レスポンスヘッダ確認は `--include`
- JSON の整形・抽出は `jq` にパイプする

## エラーハンドリング

| 症状 | 対処 |
|---|---|
| `cannot preserve mount namespace` | サンドボックスなしで再実行（snap の既知問題） |
| 401 Unauthorized | `glab auth status --hostname <host>` で確認 → 切れていたら `glab auth login --hostname <host>` をユーザーに依頼 |
| 404 Not Found | project パスのエンコード漏れ（`/` → `%2F`）、group/project の取り違え、ホスト指定漏れ（gitlab.com に飛んでいる）を疑う |
| telemetry の 401 エラー（stderr） | gitlab.com への送信失敗で無害。結果に影響しないので無視する |
