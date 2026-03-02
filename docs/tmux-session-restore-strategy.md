# tmux セッション復元戦略

## 概要

tmux再起動後に**ウィンドウ構成**と**nvimのセッション状態**を自動復元する仕組み。
2つのレイヤーで役割を明確に分離している。

## アーキテクチャ

```
tmux サーバー起動
  │
  ├─ continuum: resurrect restore を自動トリガー
  │    └─ resurrect: pane/window/layout を復元
  │         └─ @resurrect-processes: nvim プロセスを再起動
  │              └─ auto-session: バッファ・カーソル等を復元
  │
  ├─ continuum: 15分ごとに resurrect save を自動実行
  │    └─ post-save hook: fix-resurrect-defunct.sh でセーブファイル修正
  │
  └─ 手動操作: Prefix + Ctrl-h で resurrect restore
```

## 各コンポーネントの役割

### 1. tmux-continuum（自動化レイヤー）

| 設定 | 値 | 役割 |
|------|-----|------|
| `@continuum-restore` | `on` | tmux起動時にresurrectを自動実行 |
| `@continuum-save-interval` | `15` | 15分ごとにセッション自動保存 |

**設定ファイル**: `.tmux.conf:187-188`

### 2. tmux-resurrect（tmuxレイヤー）

**担当**: pane/window構成 + nvimプロセス再起動

| 設定 | 値 | 役割 |
|------|-----|------|
| `@resurrect-processes` | `"~nvim->nvim *"` | nvimを緩くマッチし、PATHのnvimで再起動 |
| `@resurrect-hook-post-save-layout` | `fix-resurrect-defunct.sh` | セーブファイルのdefunct行を修正 |
| `@resurrect-restore-key` | `C-h` | 手動復元キー（rはreloadで使用中） |

**設定ファイル**: `.tmux.conf:190-205`
**セーブファイル**: `~/.tmux/resurrect/` が存在すればそちらを優先、なければ `~/.local/share/tmux/resurrect/`（XDG）を使用

#### `"~nvim->nvim *"` の意味

- `~nvim`: AppImage等のフルパス（`/tmp/.mount_nvimXXX/usr/bin/nvim`）でも緩くマッチ
- `->nvim`: 復元時はPATHの `nvim` で起動し直す（AppImageの一時パスは再起動後に消えるため）
- `*`: 元の引数を引き継ぐ（`nvim file.txt` → そのまま `nvim file.txt` で復元）

#### fix-resurrect-defunct.sh

fish shellのzombieプロセス（`[fish] <defunct>`）がps strategyでセーブファイルのTSV形式を壊す問題への対策。

```
修正前: pane\t...\t:[fish] <defunct>     ← 壊れた行
        /tmp/.mount_nvimXXX/usr/bin/nvim  ← 孤立した実コマンド

修正後: pane\t...\t:/tmp/.mount_nvimXXX/usr/bin/nvim file.txt
```

**スクリプト**: `.tmux/scripts/fix-resurrect-defunct.sh`

### 3. auto-session（nvimレイヤー）

**担当**: nvim内部の状態復元（バッファ、カーソル位置、折り畳み、タブ等）

| 設定 | 値 | 役割 |
|------|-----|------|
| `auto_save` | `true` | 終了時にセッション自動保存 |
| `auto_restore` | `true` | 起動時にセッション自動復元 |
| `args_allow_files_auto_save` | `false` | `nvim file` 起動時はセッション保存しない |
| `suppressed_dirs` | `~`, `~/Downloads`, `/` | これらのディレクトリではセッション無効 |
| `purge_after_minutes` | `43200` | 30日超の孤児セッションを自動削除 |

**設定ファイル**: `.config/nvim/lua/my/plugins/tools/auto-session.lua`

#### シグナル対策

```lua
pre_save_cmds = {
    function()
        if vim.v.dying > 0 then return false end
    end,
}
```

`tmux kill-server` 等でSIGHUP/SIGTERM受信中はセッション保存をスキップし、壊れた状態の保存を防ぐ。

## 復元フロー詳細

### 保存時

1. continuum が15分ごとに resurrect save を実行
2. resurrect がpane/window構成 + 実行中プロセスをTSVで保存
3. post-save hook (`fix-resurrect-defunct.sh`) がdefunct行を修正
4. nvim終了時に auto-session がバッファ等をセッションファイルに保存

### 復元時

1. tmux起動 → continuum が resurrect restore を自動トリガー
2. resurrect がpane/window/layoutを復元
3. `@resurrect-processes` により nvim が再起動される
   - `nvim` のみで起動 → auto-session がディレクトリからセッション復元
   - `nvim somefile` で起動 → そのファイルが直接開く（セッション復元なし）
4. auto-session がバッファ・カーソル位置等を復元

## 設計判断

- **resurrectはnvimプロセスの起動のみ**、セッション内容の復元はauto-sessionに一元化
- **AppImage対応**: フルパスではなくPATHのnvimで起動し直す
- **引数引き継ぎ**: `*` で元の引数を保持し、ファイル直接開きにも対応
- **防御的保存**: dying状態・defunct行への対策で壊れた保存を防止
