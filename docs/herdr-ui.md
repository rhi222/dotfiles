# herdr の UI（タブ行ステータスと keybinding）

AGENTS.md の「herdr タブ行のステータス」「herdr の keybinding」の詳細。
何がどう見えるか・どのキーで何が起きるかはあちらの表にあり、ここには **なぜその実装に落ちたか**を置く。
herdr 0.8.2 時点の話。

## タブ行のステータス

- **時刻・agent usage・マシンリソースを別々の command にしている。**
  表示順を時刻 → usage → リソースに固定し、グループ間は `  │  `、リソース内は ` · ` で区切る。
  native の `datetime` は更新間隔を持たないので秒を出せず、時計も command にする

### 色の制約

- **statusline だけを着色する経路が無い。**
  0.8.2 では次の2つが同時に効く。
  ①`tab_bar_right` に色の指定フィールドが無い ②タブ行は受け取った文字列の **ESC バイトだけを落として残りを可視文字として描く**ので、スクリプトが `\033[38;5;208m` を出すと `[38;5;208m` が表示されてしまう。
  そのため `status.sh` の着色は既定 `never`。
  閾値による色分けの実装は残してあるが、これはターミナルで直接叩いたときのためのもの
- **色は theme の `overlay1` トークン頼みで、しかも statusline 専用ではない。**
  `overlay1` を検証色に振って画面全体を `pane read --format ansi` で数えたところ、**非活性タブのラベル / タブ行の `+` ボタン / statusline / オンボーディング本文**が同じ値を共有していた（活性タブは背景バッジ + 暗い文字で `overlay1` に依らない。
  非活性 workspace 名は `overlay0`）。
  **statusline を明るくすると非活性タブのラベルも一緒に変わる**ため、上書きせず素の `#697196` のままにしている。
  目立たせたくなったら、この副作用とセットで判断する

### 更新コストと欠損時の扱い

- **`clock.sh` と `status.sh` は外部コマンドを1つも呼ばない。**
  date / awk / grep / cut を素直に使った初版は実測 53ms/回で、1秒間隔だと1コアの5%を常時食う。
  bash 組み込みだけに寄せて各スクリプトを数msに抑えている。
  ここが唯一の速度要件で、可読性より優先する
- **曜日は `%a` ではなく `%w`（番号）から自前で当てる。**
  `%a` はロケール次第で表記が変わり、`LANG` を変えた端末で幅と見た目が動く。
  月日はゼロ埋めしない（`%-m/%-d`）が、時刻は桁を揃える（幅が毎秒動くのを避ける）
- **CPU% は `/proc/stat` の差分。**
  前回値を `~/.cache/herdr-status/cpu` に持つ。
  sleep で2点取る方式は毎回待つので1秒間隔と噛み合わない。
  前回値が無い初回だけ「起動からの平均」で埋める（空欄にすると herdr 起動直後だけ欄が欠けて幅が動く）
- **読めない項目は欄ごと落として exit 0。**
  1項目のためにステータス全体が消えるほうが害が大きい
- `datetime` エントリを使う場合、format は strftime だが `%z` / `%s` は拒否される（サーバーのローカル壁時計なのでオフセットとエポックの情報が無い）
- エントリは最大16個。
  超過分は `ignoring extras` で捨てられる

## keybinding

- **fzf popup に寄せているのは alt 併用キーが効かない環境のため。**
  `previous_/next_agent` や `focus_agent`（`prefix+alt+1..9`）が使えないので、単一 chord から popup を開く方式にしている
- **tab の絞り込み検索は native に無い。**
  `prefix+g` の navigate mode は h/j/k/l の空間移動、`prefix+1..9` は番号直打ちで、どちらも名前で絞れない。
  そのため `tab-switch.sh` を足している
- **tab picker には space 名を必ず併記する。**
  tab の label は既定が番号なので、複数 workspace で `1` が並んで一覧から区別できない（実機で3つの workspace が全て label `1` になっていた）
- **`prefix+t` を picker に充てた。**
  単独文字で空いていたのは `d` `i` `m` `t` `u` `y` だけで、隣の `prefix+shift+t` が `rename_tab` なので並びが揃う
- **`prefix+shift+s` が非対称なのは `prefix+s` が native の `settings` だから。**
  picker 3種を `a` / `t` / `w` に揃えるには `workspace_picker = ""` で native を潰す必要があり、そこまではしていない（native picker を残す判断）
- **fzf の終了ステータスは飲む。**
  `set -e` 下では ESC の 130 で代入ごと失敗するため、popup が「キャンセルしたのにエラー終了」になる
- 一覧の1列目は id の隠しフィールドで、`--delimiter '\t' --with-nth 2..` で表示から外す。
  選択後に `cut -f1` で取り出して `herdr <kind> focus` に渡す

## 動作確認

```fish
bash tests/session/test-herdr-status.sh
bash tests/session/test-herdr-tab-switch.sh
```

実 herdr を立てずに検証するため、`herdr` と `fzf` を PATH 前方のスタブに差し替えている。
反映は `herdr server reload-config`（`prefix+shift+r`）、検証は `herdr config check`。
