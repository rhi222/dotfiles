---
name: reveal-deck
description: reveal.js（960x540）の発表デッキをHTMLで作る・直す。決まったデザイン（淡い青の帯、装飾なしカード、いま→打ち手→変わることの3段など）の雛形と、ノート付き閲覧用HTMLの生成、PNG書き出しのスクリプトを持つ。「スライドを作って」「デッキを直して」「_reveal.htmlを更新」「発表資料をHTMLで」などで使う。既存の *_reveal.html を編集するときにも使う。
---

# reveal-deck

1つのデッキは次の3つで1組にする。直すのは `_reveal.html` だけで、残り2つはそこから作る。

| ファイル                  | 役割                                                                                                                                               |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<deck>_reveal.html`      | 発表用の正本。reveal.js 5.1.0。ノートは各スライドの `<aside class="notes">`                                                                        |
| `<deck>.html`             | 閲覧・レビュー用。スライドの下にノートを並べ、テキスト選択でコメントを付けられる。`~/.claude/skills/reveal-deck/scripts/sync_notes_html.py` で生成 |
| `<deck>_png/slide-NN.png` | 1920x1080 の画像。`~/.claude/skills/reveal-deck/scripts/export_png.sh` で生成                                                                      |

## 作業の流れ

1. 新規なら `assets/template.html` を `<deck>_reveal.html` としてコピーする。サンプル6枚（表＋注力点、課題、打ち手3段、マイルストーン、判定、まとめの流れ図）から使う型だけ残す
2. 文言・構成を直す前に、「今 → 案」の表で変更案を出して承認を得る。ユーザーが文言を指定した場合や「消して」などの明確な指示はそのまま入れてよい
3. `_reveal.html` を直す。スライド番号（`<span class="num">n / N</span>`）と、本文中の「スライドn」参照も合わせる
4. 描画してはみ出しを確かめる。はみ出したら、まず文字サイズ・幅・余白で直し、文言は変えない
   ```bash
   ~/.claude/skills/reveal-deck/scripts/export_png.sh <deck>_reveal.html /tmp/chk 3   # 3枚目だけ書き出して Read で見る
   ```
5. 閲覧用HTMLとPNGを作り直す
   ```bash
   ~/.claude/skills/reveal-deck/scripts/sync_notes_html.py <deck>_reveal.html
   ~/.claude/skills/reveal-deck/scripts/export_png.sh <deck>_reveal.html <deck>_png        # 全スライド
   ```
6. 枚数が減ったら、古い `slide-NN.png` を消す

デザインの約束事は `design-rules.md`、部品のクラスと使いどころは `components.md` を読む。

## 注意

- `<deck>.html` を手で直さない。次の生成で消える
- 別セッションが同じファイルを触ることがある。書き込む前に更新時刻を見て、自分の知らない変更があれば止めて報告する
- ノートは話す順に書く。表を読み上げない。ノートの見出し「スピーカーノート（n分）」と分量を合わせる（1分≒300字）
