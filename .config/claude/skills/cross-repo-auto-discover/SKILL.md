---
name: cross-repo-auto-discover
description: >
  会話中に外部システム・他リポジトリへの接続が検知された際、自動的にリポジトリの場所を特定して調査する。
  API呼び出し(fetch*, *Client, POST /api/, GET /v*/ 等)、外部システム名(EXAMPLE-SERVICE, SharedAPI, ExampleRecordAPI等)、
  「接続先」「他のリポジトリ」「別システム」「横断調査」「影響範囲」「呼び出し先」などの文脈で能動的に発動する。
  シーケンス図作成・アーキテクチャ調査・障害影響分析など、複数リポジトリを跨ぐタスクに使用。
  repos.yml を自動参照してエイリアス→パス解決を行い、未登録システムに遭遇した場合はユーザーに確認する。
---

# Cross-Repo Auto Discover

会話中に他リポジトリの接続先が検知されたら、能動的にリポジトリ位置を特定・調査する軽量スキル。

`cross-repo-investigate` とは役割が異なる:

| スキル                                     | 用途                                     | 発動                   | 出力                       |
| ------------------------------------------ | ---------------------------------------- | ---------------------- | -------------------------- |
| `cross-repo-investigate`                   | 公式レポート作成、影響範囲ドキュメント化 | ユーザーが明示的に呼ぶ | Obsidian Vaultにmdレポート |
| **`cross-repo-auto-discover`（本スキル）** | 会話中の軽量な接続先解決                 | 文脈から自動発動       | 会話内に簡潔な報告         |

## 発動すべきシナリオ

- ユーザーがあるリポジトリ内のコードを調査しており、そのコードが他システム（API・サービス）を呼び出している
- シーケンス図・フロー図・横断調査・影響分析などを実行中
- 「接続先は〜」「他のリポジトリ」「別システム」「呼び出し先」「依存先」などのキーワード
- 外部API呼び出し(例: `fetch*`, `POST /api/...`)や、それらしいサービス名（EXAMPLE-SERVICE, SharedAPI, example-mail等）が登場

## 発動すべきでないシナリオ

- ユーザーが1つのリポジトリ内で完結する作業をしている（ファイル編集、単体テスト等）
- 既に全接続先が判明していて、追加調査の必要がない
- 明示的に `cross-repo-investigate` スキルの呼び出しが指示された場合（そちらを優先）

## ワークフロー

### Step 1: repos.yml の読み込み

スキルディレクトリ内の `repos.yml` を Read ツールで読み込む:

```
/data/git-repos/github.com/rhi222/dotfiles/.config/claude/skills/cross-repo-auto-discover/repos.yml
```

各エントリは `path`（絶対パス）と `aliases`（エイリアス名のリスト）を持つ。

### Step 2: 接続先の抽出

会話文脈と調査対象コードから、以下のパターンで外部システム名を抽出する:

- **コード内のAPI呼び出し**: `fetchExampleCourse`, `example-serviceClient.bookingCancel`, `POST /api/batch/...` など
- **概念的な呼称**: 「ExampleRecordAPI」「ExampleContract」「ExampleMasterData」「メールAPI」など
- **URLパターン**: `https://*.example-group.jp/sharedapi/`, `/rsv/` 等

### Step 3: エイリアスマッチング

各抽出名に対して repos.yml のエイリアスと照合:

| マッチング結果       | 処理                                         |
| -------------------- | -------------------------------------------- |
| 完全一致             | 即座にパス解決                               |
| 部分一致（候補1つ）  | 自動採用し、解決結果を会話内で明示           |
| 部分一致（候補複数） | AskUserQuestion で確認                       |
| マッチなし           | 未登録の可能性を告知し、ユーザーに場所を確認 |

### Step 4: 並列調査の起動

解決されたパスを引数に、Exploreエージェントを並列で起動する（1メッセージ内で複数tool callを発行）。

各Agentに渡すプロンプト例:

```
リポジトリ `{絶対パス}` を調査してください。

目的: {会話文脈から抽出した調査目的}

以下を具体的に調べてください:
- {関連ファイル・エンドポイント・関数名の候補}
- 処理フロー（関数呼び出しチェーン）
- 外部依存（他システムへの通信）
- DB操作（あれば）
- 認証方式

thoroughness: very thorough
```

### Step 5: 結果の簡潔な報告

各Exploreエージェントの結果を集約し、**会話内で簡潔に**報告する:

- 重厚なレポート出力はしない（それは `cross-repo-investigate` の役割）
- 発見した接続先・処理フロー・懸念事項を2〜5個の箇条書きで要約
- 詳細が必要な場合はユーザーが掘り下げ指示するのを待つ

### Step 6: 新発見のフィードバック

調査中に未登録のシステムや新しいエイリアスが判明した場合:

- ユーザーに「この接続先を repos.yml に追加しますか？」と提案
- 承諾されたら repos.yml を更新

## repos.yml の形式

```yaml
- path: /data/git-repos/github.com/example-org/example-repo
  aliases: [予約, booking, example-repo]
```

- `path`: 絶対パス（必須）
- `aliases`: エイリアス名のリスト（複数可、日本語・英語混在可）

## 既存 repos.yml との関係

本スキルの `repos.yml` は `cross-repo-investigate/repos.yml` へのシンボリックリンク。
`cross-repo-investigate/repos.yml` が実体（機密データを含むため `.gitignore` 登録済み）で、
両スキルから同じマッピングを参照することで一貫した解決結果を返す。
追加・編集する際は実体ファイル側を直接編集してよい（シンボリックリンク経由で反映される）。

## Anti-patterns（やってはいけないこと）

- **推測でパスを調査する**: repos.yml にないシステムを勝手に推測した場所で調査しない（誤ったリポジトリを調査するリスク）
- **毎回重厚なレポートを出力する**: 本スキルは軽量調査。レポートが欲しければユーザーが明示的に `cross-repo-investigate` を呼ぶ
- **既知システムでもユーザーに確認**: repos.yml で完全一致するなら確認不要、即座に調査を始める

## 使用例

**例1: 自動検知が成功するケース**

```
ユーザー: 「example-repo の importExampleBooking が呼ぶ EXAMPLE-SERVICE の処理を教えて」

Claude: (repos.yml を参照、EXAMPLE-SERVICEのパス `/data/git-repos/gitlab.example.com/example-group/example-service` を解決)
        (Exploreエージェントをexample-repoとexample-serviceに並列ディスパッチ)

        「EXAMPLE-SERVICEの /v2/{coop}/booking-cancel ハンドラーは ... 」（簡潔な報告）
```

**例2: 未登録システムの検知**

```
ユーザー: 「example-repo から xyz_service への通信を調べて」

Claude: (repos.yml には xyz_service のエイリアスなし)
        「xyz_service は repos.yml に未登録です。リポジトリのパスを教えてください。
         （候補: /data/git-repos/... ）」
```
