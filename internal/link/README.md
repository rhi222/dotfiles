# link

`../../dotfilesLink.sh` の内部実装。新しい設定・skill・scriptへのsymlink追加と、既存linkの
修復を繰り返し実行できる形で行う。

雛形生成、既存ローカル設定のadopt、コピー同期、pluginの初回配置は行わない。それらは
`../bootstrap/setup.sh` が担当する。
