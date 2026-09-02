AutoHotKey用の設定ファイル

# scripts

AutoHotKeyの設定ファイル群
ホストマシンにcpして利用

ホストマシンの配備場所

```
C:\Users\<user>\Documents\AutoHotkey\
├── main.ahk
├── keymap-vimlike.ahk
└── text-snippet.ahk
```

- `bash AutoHotkey/deploy-ahk-script.sh`
  - `--dry-run` オプションで、配備先のファイル構成を確認できます。

```
C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\
└── main.ahkへのショートカット
```

- Win + R → `shell:startup` でスタートアップフォルダを開けます。

# ahk-snippets

text-snippet.ahkで利用するテキストスニペット群

`js/` と `passwords/<subsystem>/` は private-bundle の集約先
（`~/.local/share/dotfiles-private/`）へのsymlinkです。**WindowsはWSLのsymlinkを
辿れない**（`\\wsl$` でも `\\wsl.localhost` でも reparse point として見えるだけで、
列挙も存在確認も失敗する）ため、text-snippet.ahk は集約先を `PRIVATE_ROOT` として
第2のルートに持ち、リポジトリ側に見つからないスニペットをそちらから解決します。
