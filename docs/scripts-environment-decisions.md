# scriptsの環境系実装判断

[scripts-layout.md](scripts-layout.md) から分割した、env-residueとdcleanの設計記録。

## 残骸チェックの判断（env-residue）

`dotctl doctor residue` が見るのは3種類。
**既存のどのチェックにも掛からない種類の drift を埋めるためのもの**で、`doctor migration` は「リポジトリの作業状態」専用で環境は見ない。
実際にこの3種類を全部踏んだ（追跡外の `fish_user_key_bindings.fish` で Ctrl+R の修正が端末をまたぐたび戻り、vendored skill 6本が古い gh 版に隠されていた）。

| 何を見るか                                   | なぜ                                                      |
| -------------------------------------------- | --------------------------------------------------------- |
| `~/.fzf/` と `~/.fzf.bash`                   | mise 管理と二重。PATH 順で古い版を掴む端末が出る          |
| `~/.config/fish/functions/` の追跡外ファイル | Ctrl+R の担当が端末ごとに割れる原因になる                 |
| `~/.claude` `~/.codex` `~/.agents` の skill  | 宣言に無いもの、vendored なのに実ディレクトリになったもの |

- **fisher の判定は名前の規約ではなく fisher 自身が持つ一覧で行う。**
  fisher はプラグインごとに universal 変数 `_fisher_<plugin>_files` へインストールしたファイルを記録している。
  「`_` 始まりはプラグイン」で切った初版は tide の `fish_prompt` / `fish_mode_prompt` / `tide`、`fisher` 本体、fzf.fish の `fzf_configure_bindings` を**誤検知した（実環境で5件）**。
  公開関数は普通の名前を持つ
- **一覧が引けない環境では名前の規約に落とす。**
  fish が無ければ fish 関数の残骸も問題にならないので、報告漏れより誤検知を避ける側に倒す
- **skill の宣言が読めないときは skill の判定を丸ごと諦める。**
  読めないまま「宣言に無い」と言うと、正しく入っているものまで残骸に見える
- **見つかっても exit 0。**
  残骸があること自体は壊れている状態ではなく、放置すると事故になりうる状態。
  毎日 FAILED が飛ぶと無視されるようになる
- 件数は機械可読サマリ行（`env-residue: FOUND=N`）から取る。
  表示の体裁を変えても呼び出し側が壊れないようにするため（`worktree-cleanup.sh` と同じ作り）

## docker 掃除（dclean）を Go へ移した理由

`dclean` は fish 関数だったが、判定の中身が「複雑な logic を shell でやっている」最大の残りだった（fish 362行 + ヘルパー5本 + テスト905行）。

移した先は `dotctl docker clean` / `notice` / `stale` / `refresh`。
**`dclean` という呼び名は残す**（fish の補完と指の記憶がこの名前に紐づいているため）。

掃除範囲・閾値・通知の判定（`df` の Reclaimable の読み方、`--builder` / `--filter until=` の実測、orphan 判定など）は [docker-clean.md](docker-clean.md) が正で、移植で全て維持した。
ここには fish 側に残った wrapper の注意だけを置く。

### fish 側で気を付けた2点

- **`string pad` は表示幅で詰める。**
  Go の `fmt` はルーン数、bash の `printf` はバイト数なので、どちらを使っても日本語ラベルの桁が崩れる。
  表示幅を数える関数を自前で持ち、fish の `string pad` と一致することをテストで固定した
- **設定変数の受け渡しに `string collect` が要る。**
  fish のコマンド置換は改行で分割するので、付けないと除外グロブが2要素になり `env` が2つ目をコマンド名として扱う（実際に踏んだ）
