# Claude Code skill 管理の設計

AGENTS.md の「Claude Code skill管理（信頼境界と vendoring）」の詳細。導線の一覧と
コマンド表はあちらにあり、ここには**なぜそう決めたか**を置く。

## 信頼境界の作り方

- **allowlist は default-deny。** allowlist 外の owner を `skill-add.sh` /
  `setup-claude-skills.sh` に渡すと**エラーで止まり** vendor 導線が案内される。
  `claude-skills.txt` に書いた行も同じで、bootstrap（`setup-claude-skills.sh`）は
  信頼済みの行を入れ切ってから非0で終わる。**bootstrap の失敗ではなく行が1本間違って
  いる**ので、その行を `skill-vendor.sh add` に移すのが直し方になる。
  散文の規約では取りこぼすので、判定が確定する唯一の瞬間（owner を渡すところ）に
  ゲートを置いた。ゲートは**両方**に要る。片方だけだと bootstrap 経路から素通りする
- **allowlist に入れることは「人のレビューなしで毎日自動更新される」ことと同義。**
  初期値は `anthropics` / `github` / `vercel-labs` の3つだけ。個人アカウントは入れない
- **allowlist ファイルが無ければ拒否する（fail-closed）。** `secret-scan.sh` の辞書とは
  逆に倒している。辞書不在で commit できないのは困るが、allowlist 不在で skill が
  入らないのは機能が欠けるだけで害がない
- **vendored はリポジトリにコミットする。** 更新のレビュー面を `git diff` に一本化する
  ため。リポジトリ外に置くと差分を見せる仕組みを取込スクリプトが自前で持つことになり、
  その仕組みを飛ばした更新経路が必ず生まれる
- **中央の一覧ファイルは持たない。** `.vendor.json` が唯一の正で、`ls skills-vendor/` が
  一覧そのもの。`claude-skills.txt` / `gh-extensions.txt` / `package.toml` が必要だったのは
  どれも実体をリポジトリに持たないからで、vendored は前提が違う
- **`reviewed_commit` を `commit` と別に持つ。** 一致しなければ「取り込んだがレビューして
  いない」状態で、`status` と CI（`test-skill-vendor.sh`）が落とす。ファイルを手で
  書き換えて `commit` だけ進めても検知される
- **`status` は live-dir（`~/.claude/skills` / `~/.codex/skills` / `~/.agents/skills`）まで見る。**
  `preflight` は `add` のときだけ走るので、取込後に「実際に有効になっているか」を見る場所が
  無かった。**gh skill が先に入れた実ディレクトリが残っていると `safe_link` は SKIP する**ので
  symlink が張られず、Claude は古い gh 版を読み続ける。それでも `.vendor.json` は正しいため
  `status` は `[OK]` を返していた（vendoring 移行前から使っていた端末で、実際に6本すべてが
  この状態だった）。無いこと自体は異常ではない（`dotfilesLink.sh` 未実行、その agent を
  使っていない端末）ので、実ディレクトリと「別の場所を指す symlink」だけを落とす
- **audit が 0 件でも人の承認を要求する。** 平文で書かれた指示型の injection
  （「以前の指示を無視して…」）は grep では拾い切れないので、機械判定を最終判断にしない
- **未検証の skill を Claude に読ませない。** レビューの主体は人に置く。読ませた時点で
  ペイロードが会話コンテキストに入る。`skill-audit.sh` はプロンプトを一切生成しない
- **不可視文字の検出はバイト列で書かない。** `grep -P` + `\x{...}` を使う。バイト列だと
  GNU grep 3.11 と ugrep 7.8.4 で結果が食い違う（ugrep が3件中1件しか拾わない）
- **バイナリ判定は `grep -Iq`。`file --mime` は使わない。** コードブロックの多い `.md` が
  `application/javascript` と判定され、`vercel-react-best-practices` の正当な
  `rules/*.md` 27件が誤って弾かれる
- **`lint.sh` は `skills-vendor/` を除外する。** `lint.sh` は
  「ignore 済み＝自分が保守しない」で第三者コードを切る前提に立っているが、vendored は
  **追跡していながら自分は保守しない**ので、この前提の唯一の例外になる
- **`secret-scan.sh` は除外しない。** vendored に社内ホスト名や実在の値が混ざっていたら
  止めたい。誤検知はレアな手動操作なので、起きたときに対処する
- **`daily-update.sh` は検知だけ。** vendored な実体は symlink で `~/.claude/skills` へ生で
  繋がるので、作業ツリーを書き換えた瞬間に有効になる。未レビューのコードが有効になる
  瞬間を作らない
- **`local:` 行は廃止した。** shallow clone の HEAD を毎回取り直して入れるため pin も
  レビュー面も無く、3導線のうち最も無制御だった。vendoring が上位互換
- **sub-path は取込時に実物で確かめる。** upstream のディレクトリ構成は変わる。
  `.vendor.json` の `sub_path` が唯一の記録なので、`SKILL.md` の所在を見てから渡す
- vendored も `~/.claude/skills` と `~/.agents/skills` の両方へ張る。外部 skill は
  `SKILL_AGENTS` の既定で claude-code と codex の両方に入っているので、移行で見えるものを
  減らさない

動作確認は `bash scripts/test-skill-audit.sh` / `test-skill-vendor.sh` /
`test-claude-skills-allowlist.sh`。

## 動作確認

```fish
bash scripts/test-skill-audit.sh
bash scripts/test-skill-vendor.sh
bash scripts/test-claude-skills-allowlist.sh
```
