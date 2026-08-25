# ローカル設定・更新・プラグイン管理

AGENTS.md から分離した、端末固有設定の同期と各種ツール管理の詳細。
新環境での実行順序と機密ファイル台帳は [bootstrap.md](bootstrap.md) を参照する。

## private bundle

gitignore しているローカル設定・機密ファイルの実体は
`~/.local/share/dotfiles-private/` に集約し、`dotfilesLink.sh` が各所へ symlink を張る。

| 操作 | コマンド |
| ---- | -------- |
| 旧環境から集約 | `bash scripts/private-bundle.sh adopt --execute` |
| export | `bash scripts/private-bundle.sh export` |
| import | `bash scripts/private-bundle.sh import <zip>` |
| 状態確認 | `bash scripts/private-bundle.sh status` |

設計上の不変条件:

- リンク先が実ディレクトリなら1階層降り、無ければその位置をリンクする
- ファイル単位でリンクする親は `ensure_dirs` で先に作る
- export は `zip -y` で相対symlinkを保つ
- import 後は機密ファイルのpermissionを張り直す
- リンク先の実ファイルは上書きせず退避する
- `adopt` はdry-runを既定とし、変更には `--execute` を要求する
- 集約先が無い環境では `.example` からの雛形生成へフォールバックする

対象一覧は `private-bundle` 実装の `ADOPT_ENTRIES` が正。`passwords/` は直下のうち
gitがignoreしているものだけを拾う。`~/.claude/settings.json` と
`.config/codex/config.toml` は対象外。

## 書き戻される設定のコピー同期

設定を書き戻すアプリではsymlinkがtmp + renameで実ファイルに置き換わるため、実ファイルを正、
リポジトリを追従側とする。

### Claude Code settings.json

| 操作 | コマンド |
| ---- | -------- |
| 差分確認 | `bash scripts/sync-claude-settings.sh status` |
| 実ファイル → repo | `bash scripts/sync-claude-settings.sh pull` |
| repo → 実ファイル | `bash scripts/sync-claude-settings.sh push` |

- 保存時に `jq -S` で正規化する
- 両側に差分がある `push` は拒否し、明示的な `--force` だけ上書きを許す
- 不正なJSONを相手側へ伝播しない
- `daily-update.sh` のpullは差分を作るだけで、自動commitしない

### Windows設定

| repo | Windows側 |
| ---- | --------- |
| `.config/wsl/.wslconfig` | `%USERPROFILE%\.wslconfig` |
| `.config/windows-terminal/settings.json` | Terminalの `LocalState/settings.json` |

操作は `scripts/sync-windows-settings.sh status|pull|push [wslconfig|terminal]`。

- NTFS上の実体はWindowsからWSL symlinkを解釈できないためコピー同期する
- Terminalはdistro検出時に設定を書き戻すため、こちらもsymlinkにしない
- `.wslconfig` は端末のRAMに依存するので `dotfilesLink.sh` から自動pushしない
- Terminalだけ `jq -S` で正規化し、コメントを持つINIの `.wslconfig` は素通しする
- 壊れたJSON/JSONCを反対側へ伝播しない

## statusline

`ccstatusline` のレイアウトは `.config/ccstatusline/settings.json`、モデル表示は
`.config/claude/scripts/statusline-model.sh` が担当する。Fableだけ低彩度の反転バッジ、
その他は標準widget相当のcyanで表示する。

- Fableは `model.id` の `claude-fable*` と `display_name` の部分一致の両方で判定する
- `display_name` が無ければidを使い、末尾のcontext括弧書きを落とす
- `jq` が無ければ `Model: ?` を返してstatusline全体を壊さない
- `custom-command` の `preserveColors: true` を維持する

見た目の確認:

```fish
echo '{"model":{"id":"claude-fable-5","display_name":"Fable 5"},"workspace":{"current_dir":"."}}' | ccstatusline
```

## daily-update

`scripts/daily-update.sh` は apt / cargo / mise / npm / pip / nvim / gh skill /
gh extension / yazi / fisher / dotctl の既存導入物を更新し、最後にsoft checkと設定同期を行う。

- 1ステップの失敗で止めず、最後に失敗名を集約する
- worktreeとvendored skillは情報提供なので `run_step_soft` で全体をFAILEDにしない
- worktree cleanupの内部出力は字下げし、daily-updateのステップ境界と階層を分ける
- 失敗時のWindows通知はWSL2以外ではskipする
- `~/.daily-update/` の30日より古いログを起動時に削除する
- miseのshimをPATH前方へ戻してから更新する
- 新規追加は担当の宣言ファイル・setupコマンドで行い、daily-updateは更新だけを担う
- yaziは `package.toml` のrevとremote HEADを比較し、全packageが同じならupgradeをskipする。
  `package.toml` が無い環境も成功扱いでskipする
- fisherはremote commit SHAを `~/.cache/dotfiles/fisher-update.refs` に記録し、
  宣言またはSHAが変わったときだけfull reconcileする。cache削除時は次回full updateする
- dotctlはmiseによるGo更新の直後に再buildする。HEAD・build時のGo version・Go sourceが
  すべて現在値と一致すればtest/buildをskipする。test中にGo sourceが変わった場合は
  build直前にfingerprintを取り直し、build中にも変わった場合は不整合なバイナリを採用しない

## パッケージとプラグイン

| 対象 | 宣言 | 追加・reconcile | 更新 |
| ---- | ---- | --------------- | ---- |
| apt | `scripts/apt-packages.txt` | `bash scripts/apt-setup.sh` | daily-update |
| gh extension | `scripts/gh-extensions.txt` | `bash scripts/setup-gh-extensions.sh` | daily-update |
| fish | `.config/fish/fish_plugins` | `bash scripts/setup-fish-plugins.sh` | daily-update |
| yazi | `.config/yazi/package.toml` | `ya pkg add` / `bash scripts/setup-yazi-plugins.sh` | daily-update |

gh extensionは `owner/repo[@version]` 形式で、version指定はpinになる。

fisherは未宣言pluginを削除する完全reconcileなので、setupは削除対象を事前表示する。
宣言ファイルをsymlinkへ置換する前に、内容が異なる実ファイルを退避する。fish pluginが無くても
fish自体は起動できるため、`dotfilesLink.sh` から自動実行しない。

yaziは `init.lua` がpluginを `require` するため、実体が無いと起動できない。このためyaziだけは
新環境の `scripts/bootstrap.sh` からsetupを自動実行する。`ya` の終了コードだけでなく、宣言されたpluginの実体も
検査する。`package.toml` はrev/hashを持つlockfileであり、upgradeによる差分のcommitは人間が判断する。

## 自作agent skill

共用skillは `.config/agents/skills/<name>/`、Claude専用は `.config/claude/skills/<name>/`、
Codex専用は `.config/codex/skills/<name>/` を正本にする。`dotfilesLink.sh` が共用skillを
`~/.claude/skills` と `~/.agents/skills` の両方へ、専用skillを対応する片方へリンクする。

読み込み口全体はリンクせず、外部skillと共存する。削除するのはリンク切れsymlinkだけで、
正本どうしの同名衝突は拒否する。追加後は `./dotfilesLink.sh` を実行し、必要ならagentを再起動する。
