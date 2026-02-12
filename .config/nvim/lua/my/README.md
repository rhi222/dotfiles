# my/ ディレクトリ設計

## なぜ `my/` プレフィックスか

他のプラグインと名前空間をかぶらないようにするため。
たとえば `cmp.lua` という設定ファイルがあると、`require('cmp')` がプラグイン本体ではなくこのファイルを優先してしまう。

参考: https://zenn.dev/vim_jp/articles/2024-02-11-vim-update-my-init-lua

## ディレクトリ構成

```
my/
├── settings/             コアNeovim設定
│   ├── option.lua          vim.opt系の設定
│   └── autocmd.lua         autocommand定義
├── commands/             ユーザーコマンド
│   ├── init.lua            集約エントリポイント
│   ├── open-git.lua
│   ├── temporary-work.lua
│   ├── cd.lua
│   ├── cp-current-file-path.lua
│   ├── cp-to-host.lua
│   └── keymap-check.lua    :KeymapList / :KeymapCheck
└── plugins/              プラグイン管理 (lazy.nvim)
    ├── init.lua            アグリゲータ (全カテゴリを集約)
    ├── keymaps.lua         中央キーマップレジストリ
    ├── ui/                 UI系プラグイン
    │   ├── init.lua          specs (lualine, colorscheme, etc.)
    │   ├── lualine.lua
    │   ├── indent-blankline.lua
    │   ├── tokyonight.lua
    │   └── vscode.lua
    ├── lsp/                LSP・フォーマッタ
    │   ├── init.lua          specs (mason, lspconfig, conform)
    │   ├── utils.lua         共通ユーティリティ (capabilities, setup_server)
    │   ├── mason-lspconfig.lua
    │   ├── nvim-lspconfig.lua
    │   └── conform.lua
    ├── completion/         補完・AI支援
    │   ├── init.lua          specs (copilot, cmp)
    │   ├── copilot.lua
    │   ├── copilot-chat.lua
    │   └── nvim-cmp.lua
    ├── finder/             ファイル検索・ジャンプ
    │   ├── init.lua          specs (telescope, fzf-lua)
    │   ├── telescope.lua
    │   └── fzf-lua.lua
    ├── git/                Git連携
    │   ├── init.lua          specs (gitsigns, neogit)
    │   └── gitsigns.lua
    ├── editing/            テキスト編集支援
    │   ├── init.lua          specs (treesitter, hop, flash, etc.)
    │   ├── nvim-treesitter.lua
    │   └── comment.lua
    └── tools/              その他ツール
        ├── init.lua          specs (auto-session, rest, sidekick, etc.)
        ├── auto-session.lua
        └── rest-nvim.lua
```

## plugins/ の設計方針

### カテゴリ別ディレクトリ

プラグインを機能カテゴリごとにディレクトリ分け。各カテゴリは以下の構成を持つ:

- `init.lua` — lazy.nvim plugin specs（依存関係、遅延読み込み条件、keys定義）
- `<plugin-name>.lua` — 個別プラグインの詳細設定（setup呼び出し等）

設定が小さいプラグイン（`opts = {}` で済むもの）は `init.lua` に直接記述し、個別ファイルは作らない。

### ファイルの読み込みフロー

```
lazy_nvim.lua
  → require("my/plugins")          -- plugins/init.lua (アグリゲータ)
    → require("my.plugins.ui")     -- ui/init.lua
    → require("my.plugins.lsp")    -- lsp/init.lua
    → require("my.plugins.completion")
    → require("my.plugins.finder")
    → require("my.plugins.git")
    → require("my.plugins.editing")
    → require("my.plugins.tools")
```

### プラグイン追加時の手順

1. 該当カテゴリの `init.lua` に plugin spec を追加
2. 設定が複雑なら同じカテゴリに `<plugin-name>.lua` を作成し、specの `config` から require
3. keymapがあれば `keymaps.lua` にエントリを追加し、specから `km.lazy_key()` で参照

## keymap中央レジストリ (`keymaps.lua`)

### 目的

- 全keymapのlhs（キー割り当て）を一箇所で管理
- 重複検出・空きキーの把握を容易に
- キー変更時に1箇所の修正で済む

### 設計

- **lhs、mode、desc** をカテゴリ別に `keymaps.lua` で定義
- **rhs（アクション）** は各spec/configファイルに残す（プラグインAPIに依存するため）

### ヘルパー関数

| 関数 | 用途 |
|------|------|
| `km.get(category, name)` | lhs, mode, desc を返す。`vim.keymap.set` で使用 |
| `km.lazy_key(category, name, rhs, opts?)` | lazy.nvim の `keys` spec用エントリを生成 |
| `km.find_duplicates()` | 全keymapの重複を検出 |

### 使い分け

```lua
-- lazy.nvim keys spec (init.lua内)
local km = require("my.plugins.keymaps")
keys = { km.lazy_key("finder", "telescope_find_files", ":Telescope find_files<CR>") }

-- vim.keymap.set (config内)
local lhs, mode, desc = km.get("git", "toggle_blame")
vim.keymap.set(mode, lhs, gs.toggle_current_line_blame, { desc = desc })

-- プラグインAPI (config内)
local accept_key = km.get("completion", "copilot_accept")
require("copilot").setup({ suggestion = { keymap = { accept = accept_key } } })
```

### ユーザーコマンド

| コマンド | 説明 |
|----------|------|
| `:KeymapList` | 全keymapをカテゴリ・prefix別に一覧表示 |
| `:KeymapCheck` | 重複keymapを検出して警告表示 |

## keymap設計方針

### prefix体系

| prefix | 用途 | 例 |
|--------|------|-----|
| `<C-p>` + char | Finder系 | `<C-p>f` find files, `<C-p>g` live grep |
| `<space>` + char | LSP/Diagnostics | `<space>e` diagnostic, `<space>rn` rename |
| `<leader>` + char | プラグイン操作 | `<leader>g` neogit, `<leader>j` hop |
| `<leader>` + 2char | 機能グループ | `<leader>cp` copilot, `<leader>gb` blame |
| `g` + char | Go-to/Motion | `gd` definition, `gs` flash |

### 方針

- **打ちやすさ**: タイプ数を少なく
- **覚えやすさ**: prefixで統一、意味のあるニーモニック
- **副作用の少なさ**: Neovimデフォルトキーマップの上書きは限定的に

### 参考

- https://zenn.dev/vim_jp/articles/2023-05-19-vim-keybind-philosophy
- https://zenn.dev/nil2/articles/802f115673b9ba
- https://maku77.github.io/vim/keymap/current-map.html
