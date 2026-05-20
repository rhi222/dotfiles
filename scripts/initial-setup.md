# 初回セットアップ手順

`dotfilesLink.sh` でシンボリックリンクを張った後、手動で実行が必要な設定をまとめる。

## fish: universal変数で持つ設定

fish の `fish_color_*` などは universal 変数として保存する必要があり、`set -gx` ではなく `set -U` で初回1回だけ実行する。

```fish
# 自動補完の色を暗めに（tide推奨設定）
set -U fish_color_autosuggestion brblack
```

参考:

- <https://fishshell.com/docs/current/cmds/set_color.html>
- <https://reiichii.hateblo.jp/entry/2022/01/05/194823>

## tide プロンプト

`fisher install IlanCosman/tide@v6` 後、`tide configure` で初期構成。

## 日報リマインド（WSL2のみ）

`CLAUDE.md` の「日報リマインド通知」セクションを参照。

## キャッシュ初期化

`01-mise.fish` / `09-git-wt.fish` は `~/.cache/` 配下に activate 結果をキャッシュする。バイナリ更新時は自動再生成されるが、強制再生成は以下:

```fish
rm -f ~/.cache/mise-activate.fish ~/.cache/git-wt-init.fish
```
