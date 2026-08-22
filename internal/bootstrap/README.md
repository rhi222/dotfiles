# Bootstrap implementation

`../../dotfilesLink.sh` の内部実装を置く。公開入口はルートに残し、利用者や既存文書から
このディレクトリを直接呼ばない。

現在は互換性を保って実装全体を `link.sh` に移している。次にリンク処理を変更するとき、
通常リンク、private tree、agent設定、ローカル雛形の単位で分割する。
