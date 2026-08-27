# Fish Shell Configuration

このディレクトリはFish shellの設定ファイルを含みます。プラグインと個人設定を明確に分離した構造を採用しています。

## ディレクトリ構造

```
.config/fish/
├── config.fish          # メイン設定ファイル（読み込み制御のみ）
├── README.md            # このファイル
├── conf.d/              # プラグイン由来の自動読み込み設定（空/プラグイン専用）
├── functions/           # プラグイン由来の関数（空/プラグイン専用）
└── my/                  # 個人設定専用ディレクトリ
    ├── conf.d/          # 機能別設定ファイル（番号順で読み込み）
    │   ├── 00-paths.fish             # PATH設定（mise より前に読ませる）
    │   ├── 01-mise.fish              # ランタイム管理（mise）
    │   ├── 02-history.fish           # 履歴設定
    │   ├── 03-environment.fish       # 環境変数・ツール統合
    │   ├── 05-tide-settings.fish     # tideプロンプト設定変数
    │   ├── 06-aliases.fish           # エイリアス
    │   ├── 07-abbr.fish              # 略語
    │   ├── 08-prompt-override.fish   # プロンプトカスタマイズ（git treeアイコン）
    │   ├── 09-git-wt.fish            # Git worktree関連
    │   ├── 10-fzf.fish               # fzf.fishキーバインド／履歴表示設定
    │   ├── 11-yazi.fish              # yazi統合（終了時にcwdへcd）
    │   ├── 12-herdr.fish             # herdr起動ラッパー（`he`）
    │   └── 13-docker-clean.fish      # docker掃除のリマインド（起動時通知）
    ├── completions/      # カスタムコマンドの補完
    │   └── dotctl.fish   # dotctlのサブコマンド補完
    └── functions/       # カスタム関数
        ├── fish_user_key_bindings.fish       # 空定義。fzf標準統合の横取りを塞ぐ
        ├── __ghq_list_cache_path.fish    # gfのghq listキャッシュのパス解決
        ├── __ghq_list_cache_refresh.fish # 同キャッシュのアトミック更新
        ├── __git_tree_icon.fish     # プロンプト用git treeアイコン（PWDキャッシュ）
        ├── __wt_format_rows.fish    # worktree一覧の整形（main/.wt/claude タグ付け）
        ├── __wt_lock_reason.fish    # worktreeのlock理由取得
        ├── __wt_main_path.fish      # メインworktreeの絶対パス取得
        ├── __wt_select.fish         # wt/wtd共通: fzfでworktree選択
        ├── __dclean_dotctl.fish     # dotctl の場所を返す（起動時通知からも呼ぶ）
        ├── __dclean_env.fish        # fish の設定を環境変数へ移して dotctl を呼ぶ
        ├── dclean.fish              # docker掃除（dotctl docker clean の wrapper）
        ├── find_docker_compose.fish # Docker Compose自動発見
        ├── fkill.fish               # プロセス選択終了
        ├── ftmux.fish               # tmux window/session/pane選択
        ├── gf.fish                  # ghq管理リポジトリへcd（キャッシュ付き）
        ├── ghq.fish                 # ghqラッパー（get等の後にgfのキャッシュ更新）
        ├── git-fsw.fish             # Gitブランチ選択・切り替え
        ├── mv2main.fish             # mainワークツリーへmv/cp
        ├── mvuntracked.fish         # 未追跡ファイルをmainワークツリーへ移動
        ├── open-pr.fish             # 現在ブランチのPRをブラウザで開く
        ├── wt.fish                  # git worktree切り替え
        └── wtd.fish                 # git worktree削除（-f/-ff で強制削除）
```

## 設計思想

### 1. プラグイン分離

- **プラグイン用**: `conf.d/`, `functions/` （Fisher、Oh My Fishなどが使用）
- **個人設定用**: `my/conf.d/`, `my/functions/` （手動管理）

### 1.5 キーバインドの拡張点を repo 側で握る

`my/functions/fish_user_key_bindings.fish` は**中身が空なのが仕事**で、消してはいけない。

昔の `~/.fzf/install` は `~/.config/fish/functions/fish_user_key_bindings.fish` に
`fzf --fish | source` を置いていく。これは追跡外の実ファイルなので端末ごとに有無が割れ、
有る端末では fzf 標準のシェル統合が `my/conf.d` より後に走って fzf.fish の bind を
上書きする（Ctrl+R / Ctrl+T / Alt+C）。

Ctrl+R は担当が変わると読む設定変数まで変わるのが厄介で、

| 担当                              | 効く変数           | 履歴行の形            |
| --------------------------------- | ------------------ | --------------------- |
| fzf.fish `_fzf_search_history`    | `fzf_history_opts` | `MM-DD HH:MM:SS │ cmd` |
| fzf 標準 `fzf-history-widget`     | `FZF_CTRL_R_OPTS`  | タブ区切り3列         |

片方に寄せた設定はもう片方では丸ごと無効になる。そのため「一覧の時刻列を消す」修正が
端末をまたぐたび元に戻っていた（実際に2回往復している）。

`config.fish` が `my/functions` を `fish_function_path` の先頭に置くので、同名の空定義を
repo に持てば追跡外のファイルは autoload されず影になり、担当が fzf.fish 側に固定される。
手で消して回らないのは、消しても `~/.fzf/install` を踏めば復活するため。

動作確認は `bash tests/shell/test-fish-fzf-bindings.sh`。

### 1.6 .fish の構文チェック

`bash scripts/repository/lint.sh` が全 `.fish` を `fish -n`（構文チェックのみ）に掛ける。
これが無いと `conf.d` のタイポは**シェル起動時まで発覚しない**。

- 対象の集め方は `.sh` と同じ（追跡 + 未追跡、gitignore 済みと `skills-vendor/` は除外）
- `fish -n a.fish b.fish` は**1本目しか検査しない**（2本目以降は `$argv` になる）ので
  1ファイルずつ呼ぶ。1本 2ms、42本で 0.1 秒程度なので直列で足りる
- fish が無い端末では skip して成功する。fish を使わない端末で commit できなくなるのを
  避けるため。CI は fish を lint より**前に**入れて、この skip に落ちないようにしている

動作確認は `bash tests/repository/test-lint.sh`。

### 2. 機能別モジュール化

個人設定を機能ごとに分割して管理性を向上：

- **00-paths.fish**: 各種ツールのPATH設定。**mise は `~/.local/bin` に入るため、
  `01-mise.fish` より前に読ませる**（番号がそのまま依存順になる）
- **01-mise.fish**: ランタイム管理とデフォルトパッケージ
- **02-history.fish**: 履歴共有設定
- **03-environment.fish**: エディタ・zoxide・tabtab統合
- **05-tide-settings.fish**: tideプロンプト設定変数
- **06-aliases.fish**: エイリアス（Git、ツール、SSH関連）
- **07-abbr.fish**: 略語（Git、Docker、開発ツール関連）
- **08-prompt-override.fish**: プロンプトカスタマイズ（git treeアイコン）
- **09-git-wt.fish**: Git worktree関連
- **10-fzf.fish**: fzf.fishのキーバインド／履歴表示設定
- **11-yazi.fish**: yazi終了時のcwdへの自動cd（`y`関数）
- **12-herdr.fish**: herdr起動ラッパー（`he`）
- **13-docker-clean.fish**: docker掃除のリマインド（キャッシュ経由の起動時通知）

### 3. 読み込み順序制御

`config.fish`で明示的に読み込み順序を制御：

```fish
# 個人関数・補完を優先パスに追加（conf.d より前）
set -g fish_function_path ~/.config/fish/my/functions $fish_function_path
set -g fish_complete_path ~/.config/fish/my/completions $fish_complete_path

# 個人設定を順次読み込み
for file in ~/.config/fish/my/conf.d/*.fish
    if test -r $file
        source $file
    end
end
```

**`fish_function_path` の設定は conf.d の source より前に置く。** conf.d の中から
`my/functions` の関数を呼ぶ設定（`13-docker-clean.fish` など）があるため、後回しにすると
autoload に失敗して `fish_command_not_found` が走る。`mise hook-not-found` と
`/usr/lib/command-not-found` で実測 380ms を浪費するうえ、当該処理は黙って何もしない
まま終わるので気づきにくい。回帰テストは `tests/docker/test-clean.sh` の
「実際の対話シェルで通知が出る」で担保している。

## パフォーマンス最適化

### 条件付きツール初期化

未インストールツールによるエラー回避：

- `type -q mise` - miseの存在確認後に初期化
- `type -q zoxide` - zoxideの存在確認後に初期化
- `test -f ~/.config/tabtab/fish/__tabtab.fish` - tabtabファイル存在確認

### 履歴同期

`fish_postexec` イベントでコマンド実行直後に `history --merge` を実行し、他セッションの履歴を取り込む。
`fish_prompt` だと描画毎に merge が走るため、コマンド実行後だけ動く postexec を採用している。

## メンテナンス

### 新しい設定の追加

1. **エイリアス**: `06-aliases.fish`に追加
2. **略語**: `07-abbr.fish`に追加
3. **その他設定**: 機能に応じて`my/conf.d/`に新ファイル作成（番号プレフィックス付き）
4. **新しい関数**: `my/functions/`に個別ファイル作成

### プラグインの追加

Fisherやその他のプラグイン管理ツールは自動的に標準の`conf.d/`と`functions/`を使用。
個人設定との競合は発生しません。

### 設定の反映

```fish
source ~/.config/fish/config.fish
```

または新しいセッションを開始してください。

## 利点

- **競合回避**: プラグインと個人設定の明確な分離
- **管理性**: 機能別の設定ファイル分割
- **可読性**: 各ファイルの責任範囲が明確
- **拡張性**: 新機能の追加が容易
- **デバッグ性**: 問題の特定と修正が迅速
- **バージョン管理**: 個人設定のみを追跡可能
