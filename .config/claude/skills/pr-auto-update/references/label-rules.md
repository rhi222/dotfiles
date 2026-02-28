# ラベル自動設定ルール

## ラベル取得の仕組み

**優先順位**:

1. **`.github/labels.yml`**: プロジェクト固有のラベル定義から取得
2. **GitHub API**: `gh api repos/{OWNER}/{REPO}/labels --jq '.[].name'` で既存ラベルを取得

## 自動判定ルール

### ファイルパターンベース

- ドキュメント: `*.md`, `README`, `docs/` → `documentation|docs|doc` を含むラベル
- テスト: `test`, `spec` → `test|testing` を含むラベル
- CI/CD: `.github/`, `*.yml`, `Dockerfile` → `ci|build|infra|ops` を含むラベル
- 依存関係: `package.json`, `pubspec.yaml`, `requirements.txt` → `dependencies|deps` を含むラベル

### 変更内容ベース

- バグ修正: `fix|bug|error|crash|修正` → `bug|fix` を含むラベル
- 新機能: `feat|feature|add|implement|新機能|実装` → `feature|enhancement|feat` を含むラベル
- リファクタリング: `refactor|clean|リファクタ` → `refactor|cleanup|clean` を含むラベル
- パフォーマンス: `performance|perf|optimize|パフォーマンス` → `performance|perf` を含むラベル
- セキュリティ: `security|secure|セキュリティ` → `security` を含むラベル

## 制約

- **最大 3 個まで**: 自動選択されるラベル数の上限
- **既存ラベルのみ**: 新しいラベルの作成は禁止
- **部分マッチ**: ラベル名にキーワードが含まれているかで判定
