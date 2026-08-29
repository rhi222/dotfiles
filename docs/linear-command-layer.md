# Linear個人司令塔（タスク集約とAI夜間ディスパッチ）

タスクはLinear（https://linear.app/nsym・team `NSY`）に集約する。
**LinearはSoTではなく「ポインタの司令塔」**で、issueは元URL＋期待アウトカム＋判断状態だけを持つ。
本体はJira / GitHub / Slack / esa 側にある。
設計の全体像と根拠は Obsidian `01_Inbox/2026-08-06-linear-command-layer-design.md`。

| やりたいこと        | コマンド                                                               |
| ------------------- | ---------------------------------------------------------------------- |
| 初期設定（ID解決）  | `bash scripts/linear/bootstrap.sh`                                     |
| 起票                | `/linear-add`（対話skill。規約を自動適用する）                         |
| draft PR→Triage起票 | `bash scripts/linear/sweep.sh`（cron: 平日8:00）                       |
| 夜間ディスパッチ    | `bash scripts/linear/dispatch-cron.sh`（cron: 火-土1:00）              |
| Slackスタンプ起票   | `/linear-slack-sweep`（cron: 平日10:10）                               |
| 起票済みかの確認    | `/linear-recall <スレURL or キーワード>`                               |
| 動作確認            | `bash tests/linear/test-linear-api.sh` ほか `tests/linear/` の全テスト |

- 認証は `~/.config/linear/api-key`（chmod 600）、設定は `linear-bootstrap.sh` が生成する `config.json`
- 有効化フラグ: `~/.config/linear-sweep-enabled` / `~/.config/linear-dispatch-enabled` / `~/.config/linear-slack-sweep-enabled`
- **スイープはcronだけに頼らない。**
  WSL2のcronは**PCが停止していた時刻のジョブを実行せず**、anacronも入れていないため、8:00に起動していない日は丸ごと落ちる。
  `.config/fish/my/conf.d/14-linear-sweep.fish` がその日の最初の対話シェル起動時にも `--if-not-today` 付きで1回だけ走らせて取りこぼしを拾う（`$XDG_STATE_HOME` 相当の `~/.local/state/linear-sweep/last-run` で当日実行済みかを判定）。
  cronと併存しても `seen.txt` の重複排除があるので二重起票しない
- 共通ライブラリは `scripts/lib/linear-api.sh`。
  `linear_issue_create` は**assigneeを自動で自分にする**（未アサインだとMy Issuesに出ないため）

**リンクは Linear → 外部の一方向のみ。**
**GitHub / Jira には一切書き戻さない。**
どちらもチームの共有物なので、個人のタスク管理都合のノイズを持ち込まない。
「LinearのNSY-Xと紐づけました」のような紐づけコメントもしない。
ポインタはLinear側にだけ置けば足りる。

- スイープは読み取りAPIのみ使う（`gh` は `search`、Jira は GET、Slack は search と read_thread）
- 例外はagentが成果物として新規に作るPRだけ。
  そのPR本文にもLinearのidentifierを書かない
- `test-linear-sweep.sh` は gh stub が `search` 以外で呼ばれると落ちるので、これを検知できる
- Slack側の担保は許可リスト。
  `--allowedTools` に読み取り2つしか入れないことで書き込みを塞ぎ、`test-linear-slack-sweep-cron.sh` がその文字列を検査する

## 詳細設計

この文書は共通の入口と安全境界だけを扱う。
変更対象に応じて、次の設計記録を読む。

| 対象                                        | 文書                                                         |
| ------------------------------------------- | ------------------------------------------------------------ |
| state、Cycle、estimate、Project、親子issue  | [linear-state-and-planning.md](linear-state-and-planning.md) |
| Slack・draft PRからの起票、重複排除、recall | [linear-intake.md](linear-intake.md)                         |
| AI夜間dispatch、worktree、push、PR作成      | [linear-dispatch.md](linear-dispatch.md)                     |
