# Docker の掃除（dclean）

`dclean`（fish関数）で不要な Docker リソースを掃除する。fish起動時に溜まり具合を1行で通知する。

| やりたいこと | コマンド                                                                     |
| ------------ | ---------------------------------------------------------------------------- |
| 現状確認のみ | `dclean --status`                                                            |
| 軽掃除       | `dclean`（停止コンテナ / dangling image / 匿名volume / 未使用のbuild cache） |
| 重掃除       | `dclean -a`（軽 + 未使用image全部 + 共有ぶんも含むbuild cache全部）          |
| 使い方       | `dclean --help`                                                              |
| 動作確認     | `bash tests/docker/test-clean.sh`                                                  |

- **named volume は軽・重どちらでも削除しない。** `docker volume prune` に `-a` を付けないため、未使用でも named volume（DBデータ等）は残る。消すときは `docker volume rm` を明示的に叩く
- **稼働中コンテナも停止しない。** 閾値を超えて稼働しているものを一覧表示するだけで、停止するかは手動判断。一覧の下にコピペ用の停止コマンドを出し、最終行に `dclean --refresh` を添える。`--refresh` を促すのは、停止しただけでは起動時通知がキャッシュのTTLが切れるまで古い件数を出し続けるため（実際になった）。除外パターンで非表示のコンテナが閾値を超えている場合は `（除外 N 件）` を注記する（`docker ps` と件数が合わず不足に見えるのを防ぐため）
- **一覧は種別タグを出し、停止コマンドを種別ごとに分ける。** 停止の可逆性がまるで違うため。判定は Go 側の `ContainerKind` に分離してある（`internal/docker`）

| タグ           | 意味                                        | 案内するコマンド                   |
| -------------- | ------------------------------------------- | ---------------------------------- |
| `[compose]`    | compose 管理で `working_dir` が存在する     | `docker compose -p <project> down` |
| `[orphan]`     | compose 管理だが `working_dir` が消えている | 同上（ただし `up` では戻せない）   |
| `[standalone]` | compose 管理外（`docker run` 由来）         | `docker container stop <名前...>`  |

- **判定順が要点。`working_dir` label が空のときは `orphan` にせず `compose` に倒す。** `orphan` は削除を伴う `down` を案内する側なので、孤児だと証明できないものを孤児扱いしてはいけない
- **種別判定はキャッシュ読み出し時に行い、更新時に固定しない。** `test -d` は安いが、更新時に固定すると worktree を消した直後から最大6時間（TTL）`compose` と嘘をつく
- **compose 系は `stop` ではなく `docker compose -p <project> down` を案内する。** `-p` を付ければ compose ファイル無し・任意の cwd から label 経由でプロジェクトを解決でき（Compose v5.4.0 で実機確認）、compose が作った network も一緒に回収される。プロジェクト単位で1行にまとめるので、同一プロジェクトの複数コンテナで重複しない
- **`standalone` は `AutoRemove=true` のとき `※--rm: 停止で削除されます` を併記する。** レシピが docker 側に一切残らないうえ停止＝即削除になるため（実機の社内MCPコンテナがこれ）。復活は起動元のツール経由しかない
- **タグのパディングは括弧の外側に入れる**（`[main]  ` と同じ規約）。ASCII に揃えているので `string pad` の East Asian 文字幅も絡まない
- **種別表示は除外適用後の一覧に対して行う。** 既定の除外パターンはどちらも standalone なので、既定設定では `[standalone]` 行はほぼ出ない。除外リストは「知っていて放置しているもの」の宣言として残している
- **キャッシュには `schema` を持たせ、古い版は TTL 内でも stale 扱いにする。** 種別列（`compose_project` / `compose_dir` / `auto_remove`）を持たないキャッシュを読んでいる間は orphan 件数を出せないため、起動時の background 更新に乗せて次回から正しくする。`running[]` の列を増やしたら `internal/docker` の `SchemaCurrent` を上げる
- **build cache は全ビルダーを対象にする。** `docker builder prune` は `docker buildx prune` のエイリアスで `--builder` を付けないとカレントビルダーしか掃除しない。docker-containerドライバのビルダーと daemon 側の `default` ビルダーは別のキャッシュを持つ（実測で11.2GBと13.0GB）ため、`Builders` で列挙して両方に対して実行する
- **`--filter until=<duration>` は使わない。** 実測で docker / docker-container どちらのドライバでも `Total: 0B` になり、7日以上前のレコードが445件残っていても一切回収されなかった。フィルタなしなら同じ状態から5.142GB回収でき `df` の Reclaimable も 0B になる。`docker buildx du` 側も `--filter until=` を無視する（1hでも99999hでも同件数）。そのため軽/重の区別は `-a` の有無だけで付けている
- **通知は「軽掃除で消える分」と「重掃除でしか消えない分」を分けて判定する。** `docker system df` の `Images` Reclaimable は「どのコンテナからも参照されていない image」の量で dangling かは問わない。軽掃除の `image prune -f` は dangling だけを消すため、`Images` を軽掃除の根拠にすると `dclean` しても通知が消え続ける（実際になった）。`Images` 由来が主なら通知は `→ dclean -a` を案内する。`Containers` / `Local Volumes` / `Build Cache` の Reclaimable は軽掃除の prune が回収する量に対応する（実測で prune 後 0B になる）
- **軽モードは image と build cache の回収量を事前に出さない。** dangling image は共有レイヤのため確定できず、build cache は `buildx du` の合算（246件/5.4GB）と実際の回収量（0B）が桁違いになる。`df` の Build Cache Reclaimable は `default` ビルダーの分しか見ないので代わりにもならない。実際の回収量は実行後の `回収:` 行を見る
- **起動時通知は orphan が1件以上のときだけ件数を併記する**（`12h超稼働 3件（orphan 1）`）。確実な停止候補が居るかどうかで「今 `dclean --status` を見る価値があるか」が変わるため。0件なら括弧は付けない
- 意図的に未使用 image を残していて通知が邪魔な場合は `docker_clean_size_threshold_gb` を上げる
- `docker system df` は実測5.2秒かかるため、起動時通知は `$XDG_STATE_HOME/docker-clean/stats.json` のキャッシュを読むだけにしている。`dotctl docker notice` 1回で通知表示とTTL判定を行い、キャッシュが古ければ終了コード0を返す。別コマンドに分けるとdotctlのversion skew警告が2回出るため、fish側では分けない。更新は background + disown で行い、結果は次回の起動時に反映される。起動時間への影響はフックあり0.62s / なし0.63sでノイズ以下。**キャッシュを読むだけなので、コンテナを停止しても通知の件数はすぐには変わらない。** 即座に反映したいときは `dclean --refresh`（`dclean` / `dclean --status` の実行でも更新される）
- 閾値と除外リストは変数で上書きできる（`99-local.fish` などで設定する）

| 変数                              | 既定値              | 意味                                      |
| --------------------------------- | ------------------- | ----------------------------------------- |
| `docker_clean_size_threshold_gb`  | `5`                 | 回収可能サイズがこの値以上なら通知する    |
| `docker_clean_uptime_threshold_h` | `12`                | この時間を超えて稼働していたら一覧に出す  |
| `docker_clean_ignore_patterns`    | `buildx_buildkit_*` | 稼働一覧から除外する名前/イメージのグロブ |
| `docker_clean_cache_ttl_h`        | `6`                 | キャッシュのTTL                           |

除外パターンはコンテナ**名**とイメージ**名**の両方に照合する。ツールが起動するコンテナは
`suspicious_gagarin` のように名前が自動生成されるため、イメージ名でしか除外できないことがある。

**既定は buildx のビルダーだけにしている。** 常駐させている個別のコンテナは環境ごとに違うので、
除外したいものは `99-local.fish`（gitignore）で `docker_clean_ignore_patterns` に足す。

---

この文書は [AGENTS.md](../AGENTS.md) から切り出したもの。AGENTS.md 側には要点と入口だけを残してある。
