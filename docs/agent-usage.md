# agent usage の herdr 表示

herdr の tab bar と popup（prefix+u）に Claude Code / Codex のレート上限を出す。
AGENTS.md の一覧から参照される設計記録。
判定・表示を変えるときにここを読む。

## 表示

- tab bar: 通常は `CC s45% w50% f29% · CX s30% w2%`（session% / weekly% / Fable weekly%）。
  Codex override設定時は account を独立した欄に分け、`CXd s30% w2% · CXo s7% w12%` とする。
  **account は見出しで区別し、%の位置には持たせない。** `CX d0/1% o93/41%` のように1つの欄へ詰めると、
  欄の中に見出しと窓の2階層ができて、どの%がどのaccountの窓かを接頭辞1文字ずつ照合することになる。
  AI agentの見出しは大文字2文字の `CC` / `CX`、Codex accountは `CXd`（default）/ `CXo`（override）。
  枠は小文字の `s`（current session / Codexは5h）/ `w`（weekly）/ `f`（Fable weekly）に固定する。
  default が落ちて override だけ残ったときも `CXo` にする — 素性を示さないまま%だけ出すより誤読しない。
  tab bar ではreset時間を省き、絶対時刻と残り時間は popup に集約する
- `[stale]` は欄単位で末尾に1回だけ付く。Codexは欄がaccountごとに分かれているので、古い側の欄だけに付く。
  付く条件は2つ: ①`fetched_at` が15分より古い ②表示中のいずれかの窓の `resets_at` を過ぎている（窓が切り替わったのにキャッシュの%が切り替わり前のまま）。
  窓ごとには付けない
- キャッシュが無い側は欄ごと消える。
  weeklyが取れていないCodex accountも欄ごと落とす。5h窓だけが取れないときは `s` を省いて `w` だけ出す
- 詳細は prefix+u の popup（バー・絶対時刻・fetched 経過）。
  短い窓を上に置く並び（`Session 5h` → `Weekly` → `Fable wk`）はCC・CXで揃える。
  APIがreset日時を返さない未開始の窓は `reset --` とし、Unix epochや残り0分として表示しない。
  popup は通常の端末なので ANSI 色を使い、見出しを太字シアン、使用率を 60% 未満=緑 / 60%以上=黄 / 85%以上=赤、空きバーと補足を dim、stale を太字赤で表示する。
  tab bar は ANSI 非対応なので着色しない
- override有りの実データで確認済み（`line` は `CC s8% w14% f16% · CXd s0% w1% · CXo s96% w42%`、`detail` は各accountに `Session 5h` と `Weekly` の2行）

## 仕組み

- 実体は `dotctl agent-usage <line|detail|refresh>`（`internal/agentusage/`）
- `line` はキャッシュ表示専用。
  5分より古ければ自分を `refresh` で detached 起動する（tab bar の timeout 2秒内にネットワークを待たないため）。
  Claude、Codex default、設定時のCodex overrideは並列取得する。
  ロックは持たない — 60秒間隔に対し1回の refresh は最長でも20秒（各取得timeoutのうち最長）なので、多重起動しても原子書き込みが壊れないため
- キャッシュは `~/.cache/agent-usage/usage.json`。
  **%と resets_at と fetched_at のみ**。
  token・生レスポンスはファイルにもログにも残さない

## データ源と壊れ方

- Claude: `api.anthropic.com/api/oauth/usage` を `~/.claude/.credentials.json` の accessToken で GET（ヘッダ `anthropic-beta: oauth-2025-04-20`）。
  **非公式エンドポイント**（Claude Code の /usage と同じもの）で、`limits[]` の `kind: session / weekly_all / weekly_scoped` を読む。
  仕様変更・401 では fetch を err にして旧値温存 → 15分の stale 閾値を超えれば ? 表示に倒れる（それ以前に Claude Code が再起動して token が更新されれば ? は出ない）。
  access token は短命で、Claude Code をしばらく起動していない間は更新されないため、定期 refresh だけが401になることがある。
  401 の警告は `claude` の起動、再実行、解消しなければ `claude auth login` という復旧手順を出す
- Codex: `codex app-server` を stdio JSON-RPC で1往復させ、`account/rateLimits/read` の
  `rateLimits` から weekly 窓（`windowDurationMins >= 10080`）と 5h 窓（それ未満）を読む。
  **`primary` / `secondary` のどちらが5hかは決め打ちしない。** 現状の実アカウントは primary=300分・secondary=10080分だが、
  窓の長さで選べば並びが入れ替わっても壊れない。
  窓の長さを返さない応答では最初の窓をweeklyとみなし、5hは出さない（長さ不明の窓を5hと断定しない）。
  binary は `AGENT_USAGE_CODEX_BIN`（既定 `codex`）、timeout は20秒。
  defaultは呼び出し元の `CODEX_HOME` を継承する。`AGENT_USAGE_CODEX_OVERRIDE_HOME` が設定されていれば、その値を `CODEX_HOME` にした2つ目のapp-serverも起動する。
  未ログインなら JSON-RPC error になり、そのaccountだけ旧値温存に倒れる。
  override設定を外した後の正常refreshでは、cacheからoverride欄を除去する
- Codex 側は codex の実装詳細に乗っているので、壊れ方を3つ埋めてある。
  ①**応答を読み終えるまで stdin を閉じない** — app-server は stdin の EOF を終了要求として扱い、処理前に落ちる。
  ②読み出しは goroutine に逃がし、timeout を pipe の EOF に任せない — 孫プロセスが stdout を持つと親を殺しても読み出しが返らない。
  ③自前のプロセスグループにして抜けるときに孫まで殺す
- `~/.codex/sessions/**/rollout-*.jsonl` を読んでいた旧実装は codex-cli 0.149 で使えなくなった
  （`codex migrate-rollouts` が legacy 扱い、sessions/ ごと消える）。
  **このとき Refresh が片側失敗を握りつぶしていたため、exit 0・無出力のまま Codex 欄だけが消えた。**
  今は一部失敗を stderr に出す（`agent-usage refresh: codex override: ...（この側は前回値のまま）`）。
  設定された全データ源が失敗したときだけ exit 1 でキャッシュを書かない
- 既製ツールを使わなかった理由: herdr-usage（herdr プラグイン）は sidebar 表示・ statusline hook 前提で Fable の weekly_scoped を取らない。
  ccusage はトークン集計のみでクォータ%を持たない（2026-08 調査）

## 検証

    go test ./internal/agentusage/ ./internal/command/
    bash tests/session/test-herdr-usage.sh
    herdr config check

- 表示には `agent-usage` subcommand を持つ `dotctl` の install が要る。
  古い binary だと欄が黙って空になる（stdout 空・exit 2 で tab bar は壊れない）。
  `dotctl rebuild` で再ビルドする

---

この文書は [AGENTS.md](../AGENTS.md) から参照される設計記録。
AGENTS.md 側には入口だけを置く。
