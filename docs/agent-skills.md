# Agent skill 管理の設計

Claude CodeとCodexで使うskillの配置、信頼境界、vendoringの詳細。
導線の一覧とコマンド表は `AGENTS.md` に置き、ここには**なぜそう決めたか**を置く。

## 配置と配布

| 正本                                   | 用途                 | 配布先                                   |
| -------------------------------------- | -------------------- | ---------------------------------------- |
| `.config/agents/skills/<name>/`        | 自作・共用           | `~/.claude/skills` と `~/.agents/skills` |
| `.config/claude/skills/<name>/`        | Claude専用           | `~/.claude/skills`                       |
| `.config/codex/skills/<name>/`         | Codex専用            | `~/.agents/skills`                       |
| `.config/agents/skills-vendor/<name>/` | review済み外部・共用 | 両方                                     |

正本はskill単位でsymlinkし、読み込み口全体はリンクしない。外部skillの実ディレクトリと共存し、
リンク切れだけをreconcile時に削除する。同名skillが複数の正本にあれば、リンク順で有効な内容が
変わるため、どれもリンクせず衝突として報告する。

リポジトリ直下の `.agents/skills` は正本に使わない。Codexがrepository scopeとして自動検出し、
ユーザー共通の `~/.agents/skills` と二重に見えるため。中立な正本は自動探索されない
`.config/agents/skills` に置く。

agent固有のtool名、設定path、実行モデルに依存しない自作skillは共用へ置く。
変更時は `evals/evals.json` に典型的な発動例と、誤発動や過剰な断定を防ぐ境界例を置き、
出力の言い回しではなく観察可能な振る舞いをassertionにする。

## 信頼境界の作り方

### 明示呼び出し専用skill

`git-commit` は「既にstageされた差分だけをcommitする」ための明示呼び出し専用skill。
`agents/openai.yaml` の `allow_implicit_invocation: false` で通常のcommit依頼には発動させない。
skillの発動を分ける理由は、通常依頼ではCodexが今回の作業差分をstageする一方、
`$git-commit` を選ぶときはユーザーがstage範囲を決めたとみなすため。

### 取り込みと信頼

- **allowlist は default-deny。**
  allowlist 外の owner を `skill-add.sh` / `setup-claude-skills.sh` に渡すと**エラーで止まり** vendor 導線が案内される。
  `claude-skills.txt` に書いた行も同じで、bootstrap（`setup-claude-skills.sh`）は信頼済みの行を入れ切ってから非0で終わる。
  **bootstrap の失敗ではなく行が1本間違っている**ので、その行を `skill-vendor.sh add` に移すのが直し方になる。
  散文の規約では取りこぼすので、判定が確定する唯一の瞬間（owner を渡すところ）にゲートを置いた。
  ゲートは**両方**に要る。
  片方だけだと bootstrap 経路から素通りする
- **allowlist に入れることは「人のレビューなしで毎日自動更新される」ことと同義。**
  初期値は `anthropics` / `github` / `vercel-labs` の3つだけ。
  個人アカウントは入れない
- **allowlist ファイルが無ければ拒否する（fail-closed）。**
  `secret-scan.sh` の辞書とは逆に倒している。
  辞書不在で commit できないのは困るが、allowlist 不在で skill が入らないのは機能が欠けるだけで害がない
- **vendored はリポジトリにコミットする。**
  更新のレビュー面を `git diff` に一本化するため。
  リポジトリ外に置くと差分を見せる仕組みを取込スクリプトが自前で持つことになり、その仕組みを飛ばした更新経路が必ず生まれる
- **中央の一覧ファイルは持たない。**
  `.vendor.json` が唯一の正で、`ls skills-vendor/` が一覧そのもの。
  `claude-skills.txt` / `gh-extensions.txt` / `package.toml` が必要だったのはどれも実体をリポジトリに持たないからで、vendored は前提が違う

### 状態確認と監査

- **`reviewed_commit` を `commit` と別に持つ。**
  一致しなければ「取り込んだがレビューしていない」状態で、`status` と CI（`test-skill-vendor.sh`）が落とす。
  ファイルを手で書き換えて `commit` だけ進めても検知される
- **`status` は live-dir（`~/.claude/skills` / `~/.codex/skills` / `~/.agents/skills`）まで見る。**
  `preflight` は `add` のときだけ走るので、取込後に「実際に有効になっているか」を見る場所が無かった。
  **gh skill が先に入れた実ディレクトリが残っていると `safe_link` は SKIP する**ので symlink が張られず、Claude は古い gh 版を読み続ける。
  それでも `.vendor.json` は正しいため `status` は `[OK]` を返していた（vendoring 移行前から使っていた端末で、実際に6本すべてがこの状態だった）。
  無いこと自体は異常ではない（`dotfilesLink.sh` 未実行、その agent を使っていない端末）ので、実ディレクトリと「別の場所を指す symlink」だけを落とす
- **audit が 0 件でも人の承認を要求する。**
  平文で書かれた指示型の injection （「以前の指示を無視して…」）は grep では拾い切れないので、機械判定を最終判断にしない
- **未検証の skill をagentに読ませない。**
  レビューの主体は人に置く。
  読ませた時点でペイロードが会話コンテキストに入る。
  `skill-audit.sh` はプロンプトを一切生成しない
- **不可視文字の検出はバイト列で書かない。**
  `grep -P` + `\x{...}` を使う。
  バイト列だと GNU grep 3.11 と ugrep 7.8.4 で結果が食い違う（ugrep が3件中1件しか拾わない）
- **バイナリ判定は `grep -Iq`。**
  **`file --mime` は使わない。**
  コードブロックの多い `.md` が `application/javascript` と判定され、`vercel-react-best-practices` の正当な `rules/*.md` 27件が誤って弾かれる
- **`lint.sh` は `skills-vendor/` を除外する。**
  `lint.sh` は「ignore 済み＝自分が保守しない」で第三者コードを切る前提に立っているが、vendored は **追跡していながら自分は保守しない**ので、この前提の唯一の例外になる
- **`secret-scan.sh` は除外しない。**
  vendored に社内ホスト名や実在の値が混ざっていたら止めたい。
  誤検知はレアな手動操作なので、起きたときに対処する

### 更新と互換性

- **`daily-update.sh` は検知だけ。**
  vendored な実体はsymlinkで各agentの読み込み口へ生で繋がるので、作業ツリーを書き換えた瞬間に有効になる。
  未レビューのコードが有効になる瞬間を作らない。更新が複数あるときは
  `skill-vendor.sh update <name> [name...]` の一括取込コマンドを表示するが、差分表示と承認はskillごとに行う。
  1件が失敗しても残りは続行し、全体は非0で終了する
- **`local:` 行は廃止した。**
  shallow clone の HEAD を毎回取り直して入れるため pin もレビュー面も無く、3導線のうち最も無制御だった。
  vendoring が上位互換
- **sub-path は取込時に実物で確かめる。**
  upstream のディレクトリ構成は変わる。
  `.vendor.json` の `sub_path` が唯一の記録なので、`SKILL.md` の所在を見てから渡す
- vendored も `~/.claude/skills` と `~/.agents/skills` の両方へ張る。
  外部 skill は `SKILL_AGENTS` の既定で claude-code と codex の両方に入っているので、移行で見えるものを減らさない

## 動作確認

```fish
bash tests/skills/test-skill-audit.sh
bash tests/skills/test-skill-vendor.sh
bash tests/setup/test-claude-skills-allowlist.sh
```

## upstream が skill をやめることがある

`herdr` skill で実際に起きた。
`ogulcancelik/pi-extensions` は `c28f7fc` （2026-07-22 "adopt native agent tools"）で `packages/pi-herdr/skills/herdr/SKILL.md` を 195行まるごと削除し、散文の skill から Pi ネイティブの構造化ツールへ移行した。

このとき手元には**削除前に `gh skill` が入れた実ディレクトリが残っていた**。
宣言（`claude-skills.txt`）からは落としてあったので、どの導線にも属さない遺物になっていた。

- **`sub_path` が消えた upstream に pin してはいけない。**
  `status` は `git ls-remote HEAD` と `.vendor.json` の commit を比べるので、パスが無くなった upstream に pin すると**毎回「upstream の HEAD が違う」と出続け、案内される `update` は永久に失敗する**。
  `daily-update.sh` が毎日この偽アラートを出すことになり、「毎日 FAILED が飛ぶと無視されるようになる」という既存の判断と衝突する
- **skill が引っ越していないか探す。**
  herdr の場合は本体リポ `herdrdev/herdr` の `skills/herdr` が生きた upstream で、`pi-herdr` の README 自身が「standalone の skill は別途入れよ」と案内していた。
  生きた upstream から取れば `update` も回る
- **引っ越し先が無ければ持たない。**
  自作 skill として `.config/agents/skills/` などへ移すと、第三者コードを「自分が保守するもの」として抱えることになる。
  自作 / vendored の境界を曖昧にするほどの価値がある skill は稀
