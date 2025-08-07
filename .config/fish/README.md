# Fish Shell Configuration

このディレクトリはFish shellの設定ファイルを含みます。プラグインと個人設定を明確に分離した構造を採用しています。

## ディレクトリ構造

```
.config/fish/
├── config.fish          # メイン設定ファイル（エイリアス・略語・読み込み制御）
├── README.md            # このファイル
├── conf.d/              # プラグイン由来の自動読み込み設定（空/プラグイン専用）
├── functions/           # プラグイン由来の関数（空/プラグイン専用）
└── my/                  # 個人設定専用ディレクトリ
    ├── conf.d/          # 機能別設定ファイル（番号順で読み込み）
    │   ├── 01-mise.fish      # ランタイム管理（mise）
    │   ├── 02-history.fish   # 履歴設定
    │   ├── 03-environment.fish # 環境変数・ツール統合
    │   ├── 04-paths.fish     # PATH設定
    │   ├── 05-colors.fish    # 色設定
    │   └── 06-prompt.fish    # プロンプト設定（tide）
    └── functions/       # カスタム関数
        ├── find_docker_compose.fish # Docker Compose自動発見
        └── fkill.fish              # プロセス選択終了
```

## 設計思想

### 1. プラグイン分離
- **プラグイン用**: `conf.d/`, `functions/` （Fisher、Oh My Fishなどが使用）
- **個人設定用**: `my/conf.d/`, `my/functions/` （手動管理）

### 2. 機能別モジュール化
個人設定を機能ごとに分割して管理性を向上：
- **01-mise.fish**: ランタイム管理とデフォルトパッケージ
- **02-history.fish**: 履歴サイズ・重複・共有設定
- **03-environment.fish**: エディタ・zoxide・tabtab統合
- **04-paths.fish**: 各種ツールのPATH設定
- **05-colors.fish**: ターミナル色設定
- **06-prompt.fish**: tideプロンプト設定

### 3. 読み込み順序制御
`config.fish`で明示的に読み込み順序を制御：
```fish
# 個人設定を順次読み込み
for file in ~/.config/fish/my/conf.d/*.fish
    if test -r $file
        source $file
    end
end

# 個人関数を優先パスに追加
set -g fish_function_path ~/.config/fish/my/functions $fish_function_path
```

## パフォーマンス最適化

### 条件付きツール初期化
未インストールツールによるエラー回避：
- `type -q mise` - miseの存在確認後に初期化
- `type -q zoxide` - zoxideの存在確認後に初期化
- `test -f ~/.config/tabtab/fish/__tabtab.fish` - tabtabファイル存在確認

### 履歴同期の最適化
過度な頻度での実行を避けるため、10回に1回の頻度で履歴同期を実行。

## メンテナンス

### 新しい設定の追加
1. 機能に応じて`my/conf.d/`に新ファイル作成
2. 番号プレフィックスで読み込み順序制御
3. 新しい関数は`my/functions/`に個別ファイル作成

### プラグインの追加
Fisherやその他のプラグイン管理ツールは自動的に標準の`conf.d/`と`functions/`を使用。
個人設定との競合は発生しません。

### 設定の反映
```fish
source ~/.config/fish/config.fish
```
または新しいセッションを開始してください。

## 利点

- **競合回避**: プラグインと個人設定の明確な分離
- **管理性**: 機能別の設定ファイル分割
- **可読性**: 各ファイルの責任範囲が明確
- **拡張性**: 新機能の追加が容易
- **デバッグ性**: 問題の特定と修正が迅速
- **バージョン管理**: 個人設定のみを追跡可能