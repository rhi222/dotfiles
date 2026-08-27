# Bootstrap implementation

新端末・migration時に一度だけ行う初期化を置く。公開入口は
`../../scripts/setup/bootstrap.sh`。

繰り返し実行できるリンクreconcileは `../link/reconcile.sh` に分離し、公開入口
`../../dotfilesLink.sh` から呼ぶ。bootstrapは雛形生成・既存設定のadoptを済ませてから
同じreconcileを実行する。
