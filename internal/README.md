# Internal implementations

外部から直接呼ばない実装を、言語ではなく機能単位で置く。

- `scripts/` とルートの `dotfilesLink.sh` は、cron、hook、skill、文書から使う公開入口
- `internal/<feature>/` は公開入口の内部実装。GoとShellのどちらもここへ置く
- Goのunit testは対象packageと同じディレクトリ、Shellのtestは公開入口と内部APIの
  どちらも `tests/<feature>/` に置く
- 複数機能で共有する内部Shell APIだけ `internal/{automation,session,update}/` のような
  所有者を持つ場所へ置く

実装言語は処理の性質で決める。launcher、bootstrap、外部commandの直列実行はShell、
複数状態の収集・JSON・実行計画・競合判定はGoを使う。

`internal/` のパスは公開APIではない。外部参照が必要な場合は `scripts/` に互換wrapper、
source用API、またはlauncherを置く。
