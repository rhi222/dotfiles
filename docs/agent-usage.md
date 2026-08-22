# agent usage の herdr 表示

herdr の tab bar と popup（prefix+u）に Claude Code / Codex のレート上限を出す。
AGENTS.md の一覧から参照される設計記録。判定・表示を変えるときにここを読む。

## 表示

- tab bar: `CC 5h 45% (2h47m) weekly 50% fable 29% (3d11h) · CX weekly 2% (4d8h)`
  （session% / weekly% / Fable weekly% / Codex weekly%）
  AI agent の見出しは大文字2文字の `CC` / `CX` に固定し、枠は小文字の
  `5h` / `weekly` / `fable` で表す。括弧はリセットまでの残り。`5h` の括弧は session、
  `weekly 50% fable 29%` の後の括弧は
  **weekly のリセット**（Fable のリセットは line には出さず、popup では絶対時刻のみで残り時間は出さない）。
  Codex の括弧は weekly のリセット
- `[stale]` は side 単位で末尾に1回だけ付く。付く条件は2つ:
  ①`fetched_at` が15分より古い ②表示中のいずれかの窓の `resets_at` を過ぎている
  （窓が切り替わったのにキャッシュの%が切り替わり前のまま）。窓ごとには付けない
- キャッシュが無い側は欄ごと消える
- 詳細は prefix+u の popup（バー・絶対時刻・fetched 経過）。popup は通常の端末なので
  ANSI 色を使い、見出しを太字シアン、使用率を 60% 未満=緑 / 60%以上=黄 / 85%以上=赤、
  空きバーと補足を dim、stale を太字赤で表示する。tab bar は ANSI 非対応なので着色しない
- 実データで確認済み（`line` は `CC 5h 91% (1h46m) weekly 56% fable 33% (3d9h) · CX weekly 7% (6d20h)`、
  `detail` はバー・絶対リセット時刻・`fetched:` 経過付きの複数行）

## 仕組み

- 実体は `dotctl agent-usage <line|detail|refresh>`（`internal/agentusage/`）
- `line` はキャッシュ表示専用。5分より古ければ自分を `refresh` で detached 起動する
  （tab bar の timeout 2秒内にネットワークを待たないため）。ロックは持たない —
  60秒間隔 × HTTP timeout 10秒では多重起動しても原子書き込みが壊れないため
- キャッシュは `~/.cache/agent-usage/usage.json`。**%と resets_at と fetched_at のみ**。
  token・生レスポンスはファイルにもログにも残さない

## データ源と壊れ方

- Claude: `api.anthropic.com/api/oauth/usage` を `~/.claude/.credentials.json` の
  accessToken で GET（ヘッダ `anthropic-beta: oauth-2025-04-20`）。
  **非公式エンドポイント**（Claude Code の /usage と同じもの）で、`limits[]` の
  `kind: session / weekly_all / weekly_scoped` を読む。仕様変更・401 では
  fetch を err にして旧値温存 → 15分の stale 閾値を超えれば ? 表示に倒れる
  （それ以前に Claude Code が再起動して token が更新されれば ? は出ない）。
  token は Claude Code の起動で更新されるので、失効からも自然回復する
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` の最後の `rate_limits`
  （`window_minutes >= 10080` の窓）。ネットワーク不要。鮮度は最後に codex を
  使った時点だが、使っていなければ%も動かないので実用上は正確。直近3日に
  rollout が無ければ欄ごと消える
- 既製ツールを使わなかった理由: herdr-usage（herdr プラグイン）は sidebar 表示・
  statusline hook 前提で Fable の weekly_scoped を取らない。ccusage はトークン
  集計のみでクォータ%を持たない（2026-08 調査）

## 検証

    go test ./internal/agentusage/ ./internal/command/
    bash tests/session/test-herdr-usage.sh
    herdr config check

- 表示には `agent-usage` subcommand を持つ `dotctl` の install が要る。古い binary だと
  欄が黙って空になる（stdout 空・exit 2 で tab bar は壊れない）。`bash scripts/setup-dotctl.sh` で再ビルドする

---

この文書は [AGENTS.md](../AGENTS.md) から参照される設計記録。AGENTS.md 側には入口だけを置く。
