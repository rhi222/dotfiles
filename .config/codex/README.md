# Codex 設定（公式ドキュメント準拠）

Codex は **`~/.codex/config.toml`** をユーザー共通の基本設定として読み込みます。
CLI と IDE 拡張は同じ `config.toml` を共有し、CLI フラグや選択した
profile file が優先されます。

このリポジトリでは、公式の前提に合わせて設定テンプレートと自作 skill を管理します。

- `config.example.toml`: 共有テンプレート（コミット対象）
- `~/.codex/config.toml`: ローカルの実体（コミットしない）
- `rules/dotfiles.rules`: 共有するcommand rule（`~/.codex/rules/` へリンク）
- `skills/`: 自作 skill の実体（`dotfilesLink.sh` が `~/.agents/skills/` へ個別リンク）

skill はディレクトリ全体ではなく1件ずつリンクする。`~/.agents/skills/` には外部から導入した
skill も同居するためで、セットアップ時に削除するのはリンク切れの symlink だけとする。

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
GitHubは `gh pr view` / `gh pr diff` / `gh pr review` / `gh pr checkout` を自動許可する。
method次第で任意のAPI書き込みができる `gh api` は都度確認する。

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
