# Global Codex instructions

## Git commit

- 通常の「commitして」という依頼では、今回のタスクでCodexが変更したファイルだけを`git add`してcommitする
- 作業開始前から存在した変更や、タスクと無関係な変更はstageしない
- `$git-commit`を明示的に呼び出された場合はskillに従い、`git add`せずにstage済みの変更だけをcommitする
