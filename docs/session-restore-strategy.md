# セッション復元戦略

reboot 後に `he` を叩くと、ターミナルのレイアウトだけでなく **nvim と Claude / Codex のプロセス、
さらに nvim のバッファまで**復活する。その仕組みと、そう作った理由。

運用側の入口（コマンド、環境変数、`--status` の読み方）は AGENTS.md の
「セッションの復元（herdr / `he`）」にある。ここには**なぜその形なのか**を置く。

## 誰が何を復元するか

3層に分かれていて、層をまたぐ責務は持たせていない。

| 何を | 誰が | どこに保存されるか |
| --- | --- | --- |
| レイアウト / タブ名 / ペイン label / cwd | herdr 本体 | `~/.config/herdr/session.json` |
| Claude / Codex のプロセスと会話 | Herdr native agent restore | Herdr session snapshot |
| nvim のプロセス | `scripts/herdr-restore.sh` | `~/.local/state/herdr-nvim/<pane_id>` |
| nvim のバッファ・カーソル位置 | auto-session | `~/.local/share/nvim/sessions/` |

**Herdr は任意の前面プロセスを保存しない。** ただし公式 integration が session identity を報告した AI agent は、Herdr 本体が復元コマンドを組み立てられる。Claude / Codex はこちらに任せ、native restore の無い nvim だけマーカーを使う。

## マーカー方式

「復元する側がプロセスを検出する」のではなく、**各プロセスが自分で足跡を残す**。

| プロセス | マーカー | 中身 | 書く場所 |
| --- | --- | --- | --- |
| nvim | `~/.local/state/herdr-nvim/<pane_id>` | cwd（デバッグ用） | `.config/nvim/lua/my/settings/autocmd.lua` の `VimEnter` |

- **ファイル名がペイン ID、1ペイン=1ファイル。** 複数の nvim が同時に書いても排他がいらない
- **正常終了ではマーカーを消す。** `VimLeavePre` で `v:dying == 0` のときだけ削除する
- **異常終了ではマーカーが残る。** OS shutdown では `VimLeavePre` が走らない。
  つまり**残っているマーカー = 落ちる直前に動いていたペイン**になり、これがそのまま復元対象の一覧になる
- `HERDR_PANE_ID` が無い環境（herdr の外で起動した nvim）は何も書かない

nvim は cwd さえ合っていれば auto-session がバッファを戻すので、マーカーの中身はデバッグ用にすぎない。

### AI agent の session report

Claude と Codex の `SessionStart` hook は `pane report-agent-session` で session ID を Herdr へ報告する。Herdr は session snapshot にそれを保存し、server 再起動後に `claude --resume <id>` / `codex resume <id>` を使う。マーカーの残存や外部 script の投入タイミングに依存しない。

## 復元フロー

### 保存時

1. nvim が起動した時点でマーカーを書き、Claude / Codex は Herdr へ session ID を報告する
2. nvim のバッファは auto-session が**稼働中に定期保存**する（後述）
3. herdr のレイアウトは herdr 本体が `session.json` に持つ

### 復元時

1. `he` が flock を取り、サーバーが動いていなければ `herdr server` を headless で起動する
2. herdr が `session.json` からレイアウトを復元する
3. `he` が `herdr-restore.sh` を切り離して起動し、自分は TUI にアタッチする
4. client attach 後、Herdr が報告済みの Claude / Codex session を native resume する
5. `herdr-restore.sh` が nvim マーカーを読み、**生存しているペインのぶんだけ**を間隔をあけて投入する
6. 各 nvim で auto-session がバッファを復元する

**アタッチは復元完了を待たない。** 投入は数分に散るので、待つと端末が数分沈黙する。

## 一斉起動を避ける

**nvim の同時投入数と間隔を絞る。**

| 種別 | 同時投入数 | 間隔 | 環境変数 |
| --- | --- | --- | --- |
| nvim | 3 | 2秒 | `HERDR_RESTORE_NVIM_{BATCH,INTERVAL}` |

独自 wrapper の投入はフォーカス中の workspace を先にし、同一グループ内はペイン ID の辞書順にする。AI agent は Herdr 本体が attach 後に復元する。native restore には投入間隔の調整項目がないため、負荷制御より取りこぼし防止を優先した選択である。

**`he` と `herdr-restore.sh` の両方が flock を持つ。** 複数端末から同時に `he` を叩いても、
サーバー起動と復元キューはそれぞれ1プロセスだけが行う。

## 進み具合を外から見る

投入が数分に散るので、走っているのか終わったのかが分からないと「壊れた」と誤解する。
状態を `~/.local/state/herdr-restore.status` に key=value で持ち、`he --status` とトースト通知の
両方がここから文字列を組み立てる。

- **書き込みは tmp + `mv`。** 読み手が書きかけの行を読まないようにする
- **`--status` はロックより手前で処理する。** 復元中は flock が取れないので、後ろに置くと
  一番知りたいときに黙って終わる
- **触らなかったペインは skipped として数える。** 復元前から何か動いていたペインには手を出さない。
  done と total が食い違う理由が表示だけで分かるようにしている
- **`state=running` のまま pid が居なければ「中断」。** 復元プロセスが落ちたことに気づけるようにする
- **復元対象が0件なら状態ファイルも通知も触らない。** 既にサーバーが動いている状態で `he` を叩いた
  だけでトーストが飛ぶのを避ける
- **トーストの完了は待たない。** `Import-Module BurntToast` に実測10秒前後かかり、reboot 直後は
  さらに伸びる。復元キューの頭とお尻をそれで止めるのは割に合わないので `timeout` を付けて投げっぱなしにする

## nvim セッションの粒度

auto-session のセッション名は cwd 由来なので、素のままだと**同じリポジトリを2ペインで開いていると
1つのセッションファイルを共有し、最後に保存したペインの状態で上書きされる**。

そこで `custom_session_tag` に `HERDR_PANE_ID` を混ぜ、ペインごとに分ける。herdr の外で起動した
nvim は `nil` を返して従来どおり cwd 単位になる。

### フォールバック

タグ付きセッションが見つからないときだけ、cwd 単位（タグ無し）のセッションへ落ちる。タグ導入前に
保存された古いセッションや、herdr の外で作ったセッションを拾うため。タグ付けの目的は複数ペインの
上書き防止なので、読み込み側まで厳格にする必要はない。復元後の保存はタグ付きの名前で行われるので、
1回開けば自動で移行する。

**フォールバックは引数なしの起動だけで働く。** auto-session の `no_restore` フックは「タグ付きが
無かった」以外の理由でも発火するため、絞らないと事故る。

| 起動 | auto-session の判断 | `no_restore` | フォールバックさせるか |
| --- | --- | --- | --- |
| `nvim` | 復元する | 発火する | **する** |
| `nvim somefile` | `args_allow_files_auto_save = false` により復元しない | 発火する | しない |
| `nvim --headless "+Lazy! sync"` | 復元しない | 発火する | しない |
| `git diff \| nvim -`（pager） | 復元しない | 発火する | しない |

絞らなかったときは実際に事故が起きている。`nvim somefile` で開こうとしたファイルが、セッションの
内容に置き換わった。

タグ導入直後の reboot でも事故った。**読み込み側にフォールバックが無かったため、ペイン ID の
タグが付いた名前を探しに行って全部が空振りし、全ペインが空で起動した。** フォールバックはこの
後付けである。

### 稼働中の定期保存

auto-session の保存契機は `VimLeavePre` だけで、かつ `pre_save_cmds` の `v:dying` ガードにより
シグナル終了時は保存しない（書き込み途中で切られたセッションファイルの破損を避けるため）。
herdr のサーバー再起動は各ペインの nvim を SIGTERM/SIGHUP で落とすので、これだけだと
`he` がペインを復元しても「最後に `:q` で終了したときの状態」までしか戻らない。

そこで `BufEnter` / `BufWritePost` / `WinEnter` / `FocusLost` を契機に、5秒デバウンスで保存する。
終了処理中ではなく操作が落ち着いたタイミングで書くので、`v:dying` ガードを外す場合と違って
破損リスクは増えない。SIGKILL や WSL の強制終了もカバーできる。

**名前付きの listed バッファが1つも無い間は保存しない。** 復元前や素の起動直後に、空のセッションで
既存のセッションを上書きするのを防ぐ。

### スクラッチパッドを載せない

`~/.inbox.md`（`:Inbox`）と `~/.nvim_tmp/` 配下（`:Temp`）は**全プロジェクトで共有する**
スクラッチパッド。これがプロジェクト固有のセッションの表示バッファとして保存されると、
次の復元で問題が増幅する。

1. cwd 単位セッションの表示バッファがスクラッチパッドになる
2. タグ付きセッションを持たないペインがそこへフォールバックする
3. **同じ cwd の全ペインが同じスクラッチパッドを開く**
4. 定期保存が、その状態を各ペインのタグ付きセッションへ書き戻す（焼き付く。
   実際に9本のセッションが `~/.inbox.md` で埋まった）

対策として、**いずれかのウィンドウがスクラッチパッドを表示している間は保存を見送る**。
直前に保存された状態がそのまま残る。

- **バッファを消すのではなく保存を止める。** 定期保存は編集中に何度も走るので、消す実装だと
  編集中のスクラッチパッドを閉じてしまう
- **判定はウィンドウに出ているかどうかで行う。** バッファ一覧に居るだけなら復元しても画面には
  出ないので放っておく

## 旧構成（tmux-continuum + tmux-resurrect）

herdr へ移る前は tmux のプラグインでやっていた。

```
tmux サーバー起動
  └─ continuum: resurrect restore を自動トリガー
       └─ resurrect: pane/window/layout を復元
            └─ @resurrect-processes '"~nvim->nvim *"': nvim プロセスを再起動
                 └─ auto-session: バッファ・カーソル等を復元
```

3層に分ける考え方と、プロセスの再起動までしか担当せずバッファは auto-session に一元化する分担は
今も同じ。**変わったのはプロセスをどう検出するか。**

resurrect は `ps` の出力からプロセスを拾う方式で、そこが弱かった。

- **fish の zombie プロセス（`[fish] <defunct>`）が `ps` strategy の出力を壊す。** セーブファイルの
  TSV 形式が崩れ、`.tmux/scripts/fix-resurrect-defunct.sh` を post-save hook に噛ませて
  壊れた行を修正していた
- **AppImage のフルパスが再起動後に消える。** 実行時に `/tmp/.mount_nvimXXXXXX/` にマウントされる
  ため、保存されたパスは復元時に存在しない。`"~nvim->nvim *"` の `->` で「PATH の nvim で
  起動し直す」を明示していた
- `default-command` を設定すると `fish -c /usr/bin/fish` の2段階起動になり、resurrect が nvim を
  検出できなくなる。そのためコメントアウトしたままにしていた

herdr には nvim の検出機構が無いので、代わりに**プロセス側が自分でマーカーを残す**方式にした。`ps` の出力に依存しないので、zombie もフルパスも問題にならない。Claude / Codex はさらに Herdr native restore へ移し、session ID の保存と復元コマンドの組み立ても wrapper から外した。

resurrect / continuum の設定は `.config/tmux/tmux.conf` から撤去済み。
