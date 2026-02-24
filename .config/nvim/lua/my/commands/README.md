# Neovim カスタムコマンド一覧

自作のカスタムコマンドをカテゴリ別にまとめたリファレンス。

> Vim組み込みの `:command` は全プラグインのコマンドも含まれるため、ここでは自作コマンドのみを記載。

## commands/ ディレクトリ（9コマンド）

| コマンド             | ファイル                 | 説明                                                            |
| -------------------- | ------------------------ | --------------------------------------------------------------- |
| `:Inbox`             | temporary-work.lua       | `~/.inbox.md` を開く                                            |
| `:Temp <name>`       | temporary-work.lua       | `~/.nvim_tmp/tmp.<name>` を作成/編集                            |
| `:Ggr`               | cd.lua                   | gitリポジトリのルートに移動                                     |
| `:CpToHost`          | cp-to-host.lua           | WSL2でホストのDesktopにファイルコピー                           |
| `:CpCurrentFilePath` | cp-current-file-path.lua | gitルートからの相対パスをクリップボードにコピー（行番号対応）   |
| `:CpFullFilePath`    | cp-current-file-path.lua | 絶対パスをクリップボードにコピー（行番号対応）                  |
| `:OpenGit`           | open-git.lua             | GitHub/GitLab/Bitbucketでファイルをブラウザで開く（行範囲対応） |
| `:KeymapList`        | keymap-check.lua         | 登録済みキーマップをカテゴリ別に一覧表示                        |
| `:KeymapCheck`       | keymap-check.lua         | 重複キーマップを検出                                            |

## plugins/ ディレクトリ（7コマンド）

| コマンド                 | ファイル                    | 説明                                                  |
| ------------------------ | --------------------------- | ----------------------------------------------------- |
| `:Format`                | lsp/conform.lua             | コードをフォーマット（範囲選択対応）                  |
| `:FormatDisable[!]`      | lsp/conform.lua             | 保存時自動フォーマット無効化（`!`でバッファローカル） |
| `:FormatEnable`          | lsp/conform.lua             | 保存時自動フォーマット再有効化                        |
| `:CopilotChatVisual`     | completion/copilot-chat.lua | 選択テキストについてCopilotに質問                     |
| `:CopilotChatInline`     | completion/copilot-chat.lua | フローティングウィンドウでインラインチャット          |
| `:CopilotChatBuffer`     | completion/copilot-chat.lua | バッファ全体についてCopilotに質問                     |
| `:CopilotChatShowPrompt` | completion/copilot-chat.lua | 利用可能なCopilotプロンプトをTelescope表示            |

## 補足: Vim組み込みの確認方法

- `:command` — 全ユーザーコマンド一覧（プラグイン含む）
- `:command Cp` — `Cp` で始まるコマンドだけ表示（前方一致フィルタ）
