# agent usage の herdr 表示

herdr の tab bar と popup（prefix+u）に Claude Code / Codex のレート上限を出す。
AGENTS.md の一覧から参照される設計記録。
判定・表示を変えるときにここを読む。

## 表示

- tab bar: `CC s45% w50% f29% · CX w2%` （session% / weekly% / Fable weekly% / Codex weekly%） AI agent の見出しは大文字2文字の `CC` / `CX`、枠は小文字1文字の `s`（current session）/ `w`（weekly）/ `f`（Fable weekly）に固定する。
  tab bar ではreset時間を省き、絶対時刻と残り時間は popup に集約する
- `[stale]` は side 単位で末尾に1回だけ付く。
  付く条件は2つ: ①`fetched_at` が15分より古い ②表示中のいずれかの窓の `resets_at` を過ぎている（窓が切り替わったのにキャッシュの%が切り替わり前のまま）。
  窓ごとには付けない
- キャッシュが無い側は欄ごと消える
- 詳細は prefix+u の popup（バー・絶対時刻・fetched 経過）。
  popup は通常の端末なので ANSI 色を使い、見出しを太字シアン、使用率を 60% 未満=緑 / 60%以上=黄 / 85%以上=赤、空きバーと補足を dim、stale を太字赤で表示する。
  tab bar は ANSI 非対応なので着色しない
- 実データで確認済み（`line` は `CC s91% w56% f33% · CX w7%`、`detail` はバー・絶対リセット時刻・`fetched:` 経過付きの複数行）

## 仕組み

- 実体は `dotctl agent-usage <line|detail|refresh>`（`internal/agentusage/`）
- `line` はキャッシュ表示専用。
  5分より古ければ自分を `refresh` で detached 起動する（tab bar の timeout 2秒内にネットワークを待たないため）。
  ロックは持たない — 60秒間隔に対し1回の refresh は最長でも20秒（Claude 10秒 + Codex 20秒のうち遅い方）なので、多重起動しても原子書き込みが壊れないため
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
  `rateLimits` から weekly 窓（`windowDurationMins >= 10080`）を読む。
  binary は `AGENT_USAGE_CODEX_BIN`（既定 `codex`）、timeout は20秒。
  未ログインなら JSON-RPC error になり、その側だけ旧値温存に倒れる
- Codex 側は codex の実装詳細に乗っているので、壊れ方を3つ埋めてある。
  ①**応答を読み終えるまで stdin を閉じない** — app-server は stdin の EOF を終了要求として扱い、処理前に落ちる。
  ②読み出しは goroutine に逃がし、timeout を pipe の EOF に任せない — 孫プロセスが stdout を持つと親を殺しても読み出しが返らない。
  ③自前のプロセスグループにして抜けるときに孫まで殺す
- `~/.codex/sessions/**/rollout-*.jsonl` を読んでいた旧実装は codex-cli 0.149 で使えなくなった
  （`codex migrate-rollouts` が legacy 扱い、sessions/ ごと消える）。
  **このとき Refresh が片側失敗を握りつぶしていたため、exit 0・無出力のまま Codex 欄だけが消えた。**
  今は片側失敗を stderr に出す（`agent-usage refresh: codex: ...（この側は前回値のまま）`）。
  両側失敗のときだけ exit 1 でキャッシュを書かない
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
