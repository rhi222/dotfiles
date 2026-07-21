# git worktree運用の統一 設計ドキュメント

作成日: 2026-07-21

## 背景と課題

worktreeの作成経路が複数併存し、置き場所・作成後の状態がばらついている。

1. **git-wt** (`git wt <branch>`): リポジトリ内 `.wt/` に作成。`.gitconfig` の `wt.hook` で tmux新ウィンドウ+claude起動（herdr移行済みのため陳腐化）、`wt.copy = CLAUDE.md` のみコピー
2. **gwq**: `~/git-worktrees` に作成する設定だが、ほぼ未使用（`~/git-worktrees` は空）
3. **fish `wt` 関数の名前衝突**: `my/functions/wt.fish`（git-wt+fzf切り替え）が `functions/wt.fish`（`~/git-worktrees/<host>/<org>/<repo>/<branch>` 配置の自作関数）をシャドウし、後者は到達不能
4. **Claude Code内蔵**（EnterWorktree / Agent isolation）: 独自の場所に作成
5. **herdr**: エージェント用に作成

さらに、どの経路で作っても以下の手作業が必要で面倒:

- `pnpm i` のやり直し
- `.env` などgitignore対象ファイルのコピー

## 決定事項

| 論点 | 決定 |
| --- | --- |
| 方向性 | 段階的に両方やる: まず作成後処理の共通化（Phase 1）、次に経路の統一（Phase 1〜2） |
| 正規の作成ツール | git-wt に一本化。gwq と死んだ自作fish関数は廃止 |
| worktree置き場所 | リポジトリ内 `.wt/` 維持（git-wtデフォルト） |
| 作成後処理の方式 | 規約ベースで自動判定（リポジトリ側に設定ファイル不要） |
| ターミナル/エージェント自動起動 | 廃止。`wt.hook` は初期化処理専用にする |
| 差し込み層 | 案A: 共有スクリプト + 経路別配線（git post-checkout hook は husky等の `core.hooksPath` と衝突するため不採用） |

## 全体像

冪等な初期化スクリプト **`scripts/worktree-init.sh`** を単一の真実とし、どの作成経路でも最終的にこのスクリプトが走る状態を目指す。既存のcron系スクリプトと同様に `$HOME/scripts/` 配下に置く（dotfilesLink.sh のリンクパターンに従う）。

```
worktree作成
 ├─ git wt <branch>        → wt.hook が worktree-init を自動実行   [Phase 1]
 ├─ Claude Code (内蔵)     → PostToolUse hook で自動実行           [Phase 2]
 ├─ herdr                  → 仕様調査のうえ可能なら配線            [Phase 2]
 └─ 手動 git worktree add  → 手動で worktree-init を実行（1コマンド）
```

## worktree-init.sh の仕様

規約ベースの自動判定で、リポジトリ側に設定ファイルを要求しない。

- **入力**: worktreeパス（省略時はカレントディレクトリ）。git worktree内でなければエラー終了
- **元リポジトリの特定**: `git rev-parse --git-common-dir` からメインworktreeを導出
- **.env系コピー**: メインworktree内の gitignore対象 `.env*` ファイルを、相対パスを保って再帰コピー
  - monorepoのサブパッケージ配下も対象
  - `node_modules` / `.wt` 配下は除外
  - **既存ファイルは上書きしない**（冪等性の担保）
- **依存インストール**: lockファイルで自動判定
  - `pnpm-lock.yaml` → `pnpm install`
  - `package-lock.json` → `npm ci`
  - `yarn.lock` → `yarn install`
  - 該当なし → スキップ
- **オプション**: `--dry-run` で実行内容のプレビューのみ表示
- **実行順序**: .envコピー → 依存インストール（インストール失敗時もコピー済み .env は残る）
- **シェル**: bash、`set -euo pipefail`

## Phase 1: git-wt正規化と配線

1. `worktree-init.sh` をTDDで実装（テスト先行）
2. `.gitconfig` の `[wt]` セクションを書き換え
   - `hook`: tmux+claude起動 → `worktree-init` 実行に変更
   - `copy = CLAUDE.md` は維持
3. 死んだ `functions/wt.fish` を削除（`my/functions/wt.fish` のfzf切り替え関数が正規）
4. gwq廃止
   - `.config/gwq/` 削除
   - `.config/mise/config.toml` から `aqua:d-kuro/gwq` 削除
   - `07-abbr.fish` から `gw` abbr削除
5. `docs/git-worktree-tool.md` を現状に合わせて更新

## Phase 2: 他経路への配線

- **Claude Code**: `settings.json` に `PostToolUse` hook（`EnterWorktree` マッチ）を追加して `worktree-init` を自動実行。Agent の `isolation: worktree` 経路でフックが効くかは実装時に調査する
- **herdr**: worktree作成の仕組みを調査し、設定で差し込めるなら配線。無理なら手動 `worktree-init` 運用で許容する

## エラーハンドリング

- git worktree外で実行された場合は明確なエラーメッセージで終了
- メインworktreeが特定できない場合（bare repo等）はエラー終了
- 依存インストール失敗は非ゼロ終了で伝播させる（コピー済み .env はロールバックしない）

## テスト

既存の `scripts/test-nippo-check.sh` パターンに倣い **`scripts/test-worktree-init.sh`** を用意する。

- 一時ディレクトリにfixtureリポジトリを作成（gitignore対象の `.env`、サブディレクトリの `.env.local`、`pnpm-lock.yaml` を含む）
- 検証項目:
  - worktree作成 → init実行で `.env` 系がコピーされること
  - 既存ファイルが上書きされないこと（冪等性）
  - `node_modules` 配下の `.env` がコピーされないこと
  - lockファイル種別ごとのインストールコマンド判定（dry-runで検証）
  - git worktree外でのエラー終了
- TDDルールに従いテストを先に書き、失敗を確認してから実装する

## スコープ外

- worktree削除時のクリーンアップ処理（現状の `wtd` 関数で足りている）
- `~/git-worktrees` への置き場所移行（`.wt/` 維持を決定済み）
- tmux/herdrの自動起動連携（廃止を決定済み）
