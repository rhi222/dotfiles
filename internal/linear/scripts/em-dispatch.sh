#!/bin/bash
# LinearのAI Queued issueのうち、実装レーンが扱えないもの（role:managerで
# repo:行もPR URLも無い）をcodexで「叩き台＋確認質問」まで進め、My Reviewへ戻す。
#
# 有効化: touch ~/.config/linear-em-dispatch-enabled
# 無効化: rm ~/.config/linear-em-dispatch-enabled
#
# キューはLinearのstate（AI Queued）そのもの。別のキューファイルは持たない。
#
# 【重要】外部システム（Slack/Jira/esa/GitHub）へ書き込まない。
# 書き込み先はObsidian vaultとLinearコメントのみ。
set -euo pipefail

# $0 ではなく BASH_SOURCE を使う。テストが関数単体を source して呼ぶため
DOMAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/api.sh
source "$DOMAIN_DIR/lib/api.sh"
# shellcheck source=../lib/dispatch-parse.sh
source "$DOMAIN_DIR/lib/dispatch-parse.sh"

CODEX_BIN="${CODEX_BIN:-codex}"
VAULT="${NIPPO_VAULT:-$HOME/Obsidian}"
EM_SCHEMA="${LINEAR_EM_SCHEMA:-$DOMAIN_DIR/schema/em-output.schema.json}"
EM_STATE_DIR="${LINEAR_EM_STATE_DIR:-$HOME/.local/state/linear-em-dispatch}"
EM_LOCK="$EM_STATE_DIR/em.lock"
LINEAR_WIP_LIMIT="${LINEAR_WIP_LIMIT:-10}"
LINEAR_EM_DISPATCH_MAX="${LINEAR_EM_DISPATCH_MAX:-3}"
LINEAR_EM_TIMEOUT="${LINEAR_EM_TIMEOUT:-900}"

# em_is_em_lane <issue-json>
# EMレーンが扱う対象なら0。実装レーンの担当・委譲不可なら非0。
#
# 判定は3つ。role:manager を持つ / ai:blocked-human を持たない /
# 本文に repo: 行もPR URLも無い。ラベルを判別子に使うのは、これが
# パイプライン上の位置ではなく「どちらのランナーが扱えるか」という
# 属性だから（ai:blocked-human がstateと直交しているのと同じ理由）
#
# `A && return 1` と書かないこと。Aが失敗するとリスト全体が非0を返し、
# set -e が効く文脈では関数ではなくスクリプトごと落ちる。必ず if で書く
em_is_em_lane() {
  local issue="$1" desc
  if ! jq -e '[.labels.nodes[].name] | index("role:manager")' <<<"$issue" >/dev/null 2>&1; then
    return 1
  fi
  if jq -e '[.labels.nodes[].name] | index("ai:blocked-human")' <<<"$issue" >/dev/null 2>&1; then
    return 1
  fi
  desc=$(jq -r '.description // ""' <<<"$issue")
  if dispatch_parse_repo "$desc" >/dev/null 2>&1; then
    return 1
  fi
  if dispatch_parse_pr_url "$desc" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# em_build_prompt <issue-json> → プロンプト文字列
#
# codex exec は新しいプロセスで呼び出し側の文脈を一切持たない。
# 参照すべきノート・成果物の置き場・制約をすべて明示的に渡す。
# vault直下のAGENTS.mdはcodexが自動で読むので、ここでは重複させない
em_build_prompt() {
  local issue="$1" identifier title desc weekly
  identifier=$(jq -r '.identifier' <<<"$issue")
  title=$(jq -r '.title' <<<"$issue")
  desc=$(jq -r '.description // ""' <<<"$issue")
  # 直近の週次レポート。無ければその行を落とす
  weekly=$(ls -1 "$VAULT"/02_Daily/weekly/*/nippo-weekly.*.md 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$weekly" ]]; then
    weekly="- ${weekly#"$VAULT"/}"
  fi

  cat <<PROMPT
あなたはエンジニアリングマネージャーの補助です。
次のLinear issueについて、叩き台と確認質問を作ってください。

# 対象: $identifier $title

$desc

# 先に読むもの

- 02_Daily/config/nippo-goals.md
$weekly

# 成果物

叩き台を \`01_Inbox/ai/${identifier}-<slug>.md\` に書き出してください。
\`<slug>\` はタイトルから記号と空白を除いた短い日本語にしてください。
書き出したパスを draft_path として返してください。

# 確認質問

本人にしか決められないことを3〜5個挙げてください。
調べれば分かることは質問にせず、自分で調べて叩き台に反映してください。
各質問には選択肢を2〜4個付け、なぜ自分で決められないのかを1文で添えてください。

# 制約

- Slack・Jira・esa・GitHub へは一切書き込まない
- vault の外へ書き込まない
- 既存ノートを要約・削除・書き換えない
PROMPT
}

# em_run_codex <issue-json> <out_json> <log_file> → codexの終了コード
#
# stdinを閉じないと "Reading additional input from stdin..." でEOFを待ち続けて
# 固まる。バックグラウンド起動では必ず踏むので、ここで固定する
em_run_codex() {
  local issue="$1" out_json="$2" log_file="$3" prompt
  prompt=$(em_build_prompt "$issue")
  timeout "$LINEAR_EM_TIMEOUT" "$CODEX_BIN" exec \
    -C "$VAULT" \
    -s workspace-write \
    --output-schema "$EM_SCHEMA" \
    -o "$out_json" \
    "$prompt" \
    </dev/null >"$log_file" 2>&1
}

# em_validate_output <out_json>
# 妥当なら0。--output-schema で形は既に縛られているので、ここで見るのは
# 「codexが約束を守ったか」の3点だけ（必須キー・質問件数・成果物の実在）
em_validate_output() {
  local out_json="$1" draft
  jq -e . "$out_json" >/dev/null 2>&1 || {
    echo "出力がJSONとして壊れている" >&2
    return 1
  }
  jq -e 'has("draft_path") and has("summary") and has("questions") and has("next_action")' \
    "$out_json" >/dev/null || {
    echo "必須キーが欠けている" >&2
    return 1
  }
  jq -e '(.questions | length) >= 3' "$out_json" >/dev/null || {
    echo "確認質問が3件未満" >&2
    return 1
  }
  draft=$(jq -r '.draft_path' "$out_json")
  [[ -f "$VAULT/$draft" ]] || {
    echo "draft_pathのファイルが無い: $draft" >&2
    return 1
  }
  return 0
}

# em_questions_markdown <out_json> → Linearコメント本文
em_questions_markdown() {
  local out_json="$1"
  {
    echo "Codex叩き台完了"
    echo ""
    echo "成果物: \`$(jq -r '.draft_path' "$out_json")\`"
    echo ""
    echo "$(jq -r '.summary' "$out_json")"
    echo ""
    echo "## 確認したいこと"
    jq -r '.questions | to_entries[]
      | "\n### \(.key + 1). \(.value.q)\n\n\(.value.why)\n\n"
        + (.value.options | to_entries
           | map("- \(.key + 1)) \(.value)") | join("\n"))' "$out_json"
    echo ""
    echo "次の一手: $(jq -r '.next_action' "$out_json")"
  }
}

# em_finish_failed <issueId> <identifier> <log> <理由>
# 理由とログ末尾をコメントしてTodoへ差し戻す（黙って消えないようにする）
em_finish_failed() {
  local id="$1" identifier="$2" log="$3" reason="$4"
  linear_comment "$id" "EMレーンdispatch失敗: ${reason}

ログ末尾:

\`\`\`
$(tail -20 <<<"$log")
\`\`\`" || echo "警告: 失敗コメントを残せなかった（$identifier）" >&2
  linear_issue_move "$id" "Todo" || echo "警告: Todoへ戻せなかった（$identifier）" >&2
  echo "$identifier: FAILED ($reason)"
}

# em_dispatch_one <issue-json>
em_dispatch_one() {
  local issue="$1" id identifier out_json log_file log status
  id=$(jq -r '.id' <<<"$issue")
  identifier=$(jq -r '.identifier' <<<"$issue")
  mkdir -p "$EM_STATE_DIR"
  out_json="$EM_STATE_DIR/$identifier.json"
  log_file="$EM_STATE_DIR/$identifier.log"

  # AI Running への遷移が通らないまま進むと、次の起動でも AI Queued として
  # 拾われて同じ叩き台を二重に作ることになる。通らなければ着手しない
  if ! linear_issue_move "$id" "AI Running"; then
    echo "$identifier: SKIPPED (AI Runningへ遷移できなかった)"
    return 0
  fi

  set +e
  em_run_codex "$issue" "$out_json" "$log_file"
  status=$?
  set -e
  log=$(cat "$log_file" 2>/dev/null || echo "")

  if [[ $status -eq 124 ]]; then
    em_finish_failed "$id" "$identifier" "$log" "codex実行が${LINEAR_EM_TIMEOUT}秒でタイムアウトした"
    return 0
  fi
  if [[ $status -ne 0 ]]; then
    em_finish_failed "$id" "$identifier" "$log" "codex実行が異常終了した（exit $status）"
    return 0
  fi
  if ! em_validate_output "$out_json" 2>"$EM_STATE_DIR/$identifier.err"; then
    em_finish_failed "$id" "$identifier" \
      "$(cat "$EM_STATE_DIR/$identifier.err" 2>/dev/null)" "codexの出力が契約を満たさない"
    return 0
  fi

  linear_comment "$id" "$(em_questions_markdown "$out_json")" ||
    echo "警告: 質問コメントを残せなかった（$identifier）" >&2
  # ここまで来れば成果物は出来ている。state遷移に失敗しても成果は残るので止めない
  linear_issue_move "$id" "My Review" ||
    echo "警告: My Reviewへ遷移できなかった（$identifier）。手で移してほしい" >&2
  echo "$identifier: OK $(jq -r '.draft_path' "$out_json")"
}

# em_run_batch
# AI Queued のうちEMレーン対象を上限まで処理する。処理後に再スキャンし、
# 実行中に足されたものも拾う（Linearのstateがキューそのものなので、
# 別のキューファイルを持たずにこれで済む）
em_run_batch() {
  local processed=0 ready targets count issue
  while [[ "$processed" -lt "$LINEAR_EM_DISPATCH_MAX" ]]; do
    ready=$(linear_issues_in_state "AI Queued") || break
    targets="[]"
    while read -r issue; do
      [[ -n "$issue" ]] || continue
      if em_is_em_lane "$issue"; then
        targets=$(jq -c --argjson i "$issue" '. + [$i]' <<<"$targets")
      fi
    done < <(jq -c '.[]' <<<"$ready")
    count=$(jq 'length' <<<"$targets")
    if [[ "$count" -eq 0 ]]; then
      break
    fi
    issue=$(jq -c '.[0]' <<<"$targets")
    em_dispatch_one "$issue" || echo "警告: 1件が異常終了した。次へ進む" >&2
    processed=$((processed + 1))
  done
  echo "$(date): em-dispatch done (processed=$processed)"
}

main() {
  [[ -f "$HOME/.config/linear-em-dispatch-enabled" ]] || exit 0
  local sub="${1:-run}" wip

  case "$sub" in
    run)
      wip=$(linear_issues_in_state "My Review" | jq 'length')
      if [[ "$wip" -ge "$LINEAR_WIP_LIMIT" ]]; then
        echo "$(date): WIP上限（My Review ${wip}件 >= ${LINEAR_WIP_LIMIT}）。EMレーンをスキップ。朝の判断タイムで捌いてほしい"
        exit 0
      fi
      mkdir -p "$EM_STATE_DIR"
      # 同時に1本だけ走らせる。取れなければ既にワーカーが動いている
      exec 9>"$EM_LOCK"
      if ! flock -n 9; then
        echo "$(date): 既にワーカーが動いている。何もしない"
        exit 0
      fi
      em_run_batch
      ;;
    *)
      echo "usage: em-dispatch.sh [run]" >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
