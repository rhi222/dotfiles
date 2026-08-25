# Codex 設定（公式ドキュメント準拠）

Codex は **`~/.codex/config.toml`** をユーザー共通の基本設定として読み込みます。
CLI と IDE 拡張は同じ `config.toml` を共有し、CLI フラグや選択した
profile file が優先されます。

このリポジトリでは、公式の前提に合わせて設定テンプレートと自作 skill を管理します。

- `config.example.toml`: 共有テンプレート（コミット対象）
- `~/.codex/config.toml`: ローカルの実体（コミットしない）
- `rules/dotfiles.rules`: 共有するcommand rule（`~/.codex/rules/` へリンク）
- `hooks.json` / `hooks/herdr-agent-session.sh`: Herdr native restore 用の session report
- `skills/`: 自作 skill の実体（`dotfilesLink.sh` が `~/.agents/skills/` へ個別リンク）

skill はディレクトリ全体ではなく1件ずつリンクする。`~/.agents/skills/` には外部から導入した
skill も同居するためで、セットアップ時に削除するのはリンク切れの symlink だけとする。

## CLI account の端末・repository別切り替え

Fish の `codex` wrapper は、ローカル設定で登録したrepositoryだけ別の `CODEX_HOME` で
Codex CLIを起動する。`CODEX_HOME` は認証だけでなくsession、history、log、cacheも分ける。
両homeの `config.toml` では `cli_auth_credentials_store = "file"` を使い、認証情報を
それぞれの `auth.json` に物理的に分離する。`auth.json` はtokenを含むため、repository、
private bundle、チャットへ入れない。

端末ごとの使い分けは次のとおり。

- 個人PC: ローカル変数を設定せず、通常の `~/.codex` をprivate accountとして使う
- 会社PC: 通常の `~/.codex` を社用accountとし、指定repositoryだけprivate用homeへ切り替える

会社PCでは、gitignore済みの `.config/fish/my/conf.d/99-local.fish` に実値を設定する。
repository rootは完全一致で判定するため、切り替えたいworktreeも個別に登録する。

```fish
set -g codex_alt_repo_roots \
    $HOME/path/to/example-org/example-repo \
    $HOME/path/to/worktrees/example-repo-topic
set -g codex_alt_home $HOME/.codex-private
set -gx AGENT_USAGE_CODEX_OVERRIDE_HOME $codex_alt_home
```

`AGENT_USAGE_CODEX_OVERRIDE_HOME` は `dotctl agent-usage` がdefaultとprivate両方のweekly上限を
取得するためのexport値。設定後は新しいFishからHerdrを起動し直し、server processにも反映する。
個人PCでは設定せず、従来どおりdefault accountだけを表示する。

private用homeは所有者限定で作り、共通設定と共有ruleだけを個別にlinkする。home全体や
`auth.json` をlinkしてはならない。端末固有の `default.rules` は共有しない。

```fish
mkdir -m 700 $codex_alt_home
ln -s ~/.codex/config.toml $codex_alt_home/config.toml
ln -s ~/.codex/hooks.json $codex_alt_home/hooks.json
mkdir -p $codex_alt_home/rules
ln -s ~/.codex/rules/dotfiles.rules $codex_alt_home/rules/dotfiles.rules
```

既存fileがある場合は上書きせず、内容を確認して退避する。対象外repositoryで社用account、
対象repositoryでprivate accountへそれぞれログインする。

```fish
codex login status
cd $codex_alt_repo_roots[1]
codex login
codex login status
```

`codex login status` は認証方式とログイン有無だけを表示し、CLIにはaccountやworkspaceの
識別情報を確認するprofile表示が無い。`codex login` のブラウザフロー中にChatGPTのprofile
menuで選択中accountとworkspaceを確認する。誤選択を避けるには社用・privateでbrowser profileを
分ける。対象repositoryなのに `codex_alt_home` が空なら、wrapperは通常accountへのfallbackを
拒否する。`exec`、`resume`、`login`、`logout` を含む全subcommandに同じ選択が適用される。

## 運用フロー（最小・安全）

1. テンプレートから実体を作成（初回のみ）

   ```bash
   mkdir -p ~/.codex
   cp .config/codex/config.example.toml ~/.codex/config.toml
   ```

2. ローカル設定を編集（Trusted Roots など）

3. 設定キーを厳格に検査

   ```bash
   codex --strict-config
   ```

   TUI が起動すれば設定は正常。未知のキーがあれば起動前にエラーになる。

4. 1回だけの上書きは CLI で実行

   ```bash
   codex --config model='"gpt-5.6-terra"'
   ```

`--config` などの CLI での上書きは `config.toml` よりも優先されます。

named profile は `config.toml` 内の `[profiles.<name>]` ではなく、
`~/.codex/<name>.config.toml` へトップレベルの設定キーを書く。

```bash
codex --profile <name>
```

command allowlist は `config.toml` ではなく `.rules` に置く。共有ruleは
`dotfiles.rules`、TUIが書き込む端末固有ruleは `default.rules` として共存させる。
Gitは直接の `git commit`、GitHubは `gh pr view` / `gh pr diff` / `gh pr review` /
`gh pr checkout` を自動許可する。`git push` と、method次第で任意のAPI書き込みができる
`gh api` は都度確認する。

`config.example.toml` はGitHub pluginの有効状態も共有するが、plugin本体のinstallは行わない。
新環境ではCodexのplugin管理画面またはCLIから別途installする。

`notice.*` と `tui.model_availability_nux` はCodexが書き込む確認済み状態なので、
ローカルの実体だけに残し、共有テンプレートへは取り込まない。

## 更新フロー（テンプレート反映）

ローカル設定は手元の裁量で変わるため、テンプレートの差分だけを安全に取り込みます。

1. テンプレートを退避して比較

   ```bash
   cp ~/.codex/config.toml /tmp/codex.config.toml.bak
   diff -u /tmp/codex.config.toml.bak .config/codex/config.example.toml
   ```

2. 必要な差分だけを手動で反映

## よくある運用パターン

- **日常運用**: `~/.codex/config.toml` を基準に編集
- **一時変更**: `codex --config ...` で上書き（終了後に戻る）
- **テンプレート更新**: 上記の「更新フロー」で差分反映

## 参考（公式）

- 設定ファイルの場所と優先順位: `~/.codex/config.toml` / CLI / profiles / root values
- CLI の `--config` 上書き: 1回だけの設定変更
