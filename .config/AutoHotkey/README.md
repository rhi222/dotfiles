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
