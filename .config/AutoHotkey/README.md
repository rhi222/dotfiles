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

- `cp AutoHotkey/scripts/* /mnt/c/Users/<user>/Documents/AutoHotkey/`

```
C:\Users\<user>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\
└── main.ahkへのショートカット
```

- Win + R → `shell:startup` でスタートアップフォルダを開けます。

# ahk-snippets

text-snippet.ahkで利用するテキストスニペット群
