# Codex 設定（公式ドキュメント準拠）

Codex は **`~/.codex/config.toml`** を単一の設定ファイルとして読み込みます。
CLI と IDE 拡張は同じ `config.toml` を共有し、CLI フラグやプロファイルが優先されます。

このリポジトリでは、公式の前提に合わせて **テンプレートのみ** を管理します。

- `config.example.toml`: 共有テンプレート（コミット対象）
- `~/.codex/config.toml`: ローカルの実体（コミットしない）

## 運用フロー（最小・安全）

1. テンプレートから実体を作成（初回のみ）

   ```bash
   mkdir -p ~/.codex
   cp .config/codex/config.example.toml ~/.codex/config.toml
   ```

2. ローカル設定を編集（Trusted Roots など）

3. 1回だけの上書きは CLI で実行

   ```bash
   codex --config model='"gpt-5.2"'
   ```

`--config` などの CLI での上書きは `config.toml` よりも優先されます。

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
