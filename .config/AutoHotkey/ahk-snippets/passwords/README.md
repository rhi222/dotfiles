# passwords ディレクトリ

ローカルサービスの認証情報を管理するディレクトリ。
AHKスニペット (`text-snippet.ahk`) が自動スキャンし、ホットストリングとGUIメニューを生成する。

## ディレクトリ構造

```
passwords/
├── {サブシステム名}/
│   ├── {環境名}/
│   │   ├── id.txt
│   │   └── pass.txt
│   └── {環境名}/
│       ├── id.txt
│       └── pass.txt
└── ...
```

3層構造（サブシステム / 環境 / ファイル）を厳守すること。

## ファイル配置ルール

- サブシステム名・環境名にはハイフン `-` を使用可（スペースは不可）
- 認証ファイルの拡張子は任意（`.txt` 推奨）
- ファイル内容は改行なしの1行テキスト
- `.gitkeep` と `README.md` 以外のファイルは `.gitignore` で除外済み

## 使い方

### 1. フォルダとファイルを作成

```
passwords/hoge-system/dev/id.txt    → 中身: admin
passwords/hoge-system/dev/pass.txt  → 中身: P@ssw0rd
```

### 2. AHKをリロード

### 3. 利用方法（2通り）

- **ホットストリング**: `;pw-hoge-system-dev-id` と入力 → クリップボード経由でペースト
- **GUIメニュー**: `Ctrl+Alt+S` → Passwords → hoge-system → dev → id

## トリガー命名規則

```
;pw-{サブシステム名}-{環境名}-{ファイル名（拡張子なし）}
```

例: `passwords/my-app/staging/pass.txt` → `;pw-my-app-staging-pass`
