#!/bin/bash
# explain-doc skillの構造（frontmatter、references、自己チェックID、evals、doc-refineからの参照）を検査する。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ROOT/.config/agents/skills/explain-doc"
REFINE="$ROOT/.config/claude/skills/doc-refine/SKILL.md"
fail=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    fail=1
  fi
}

check "SKILL.mdがある" test -f "$SKILL/SKILL.md"
FRONT="$(sed -n '2,/^---$/p' "$SKILL/SKILL.md" 2>/dev/null)"
check "frontmatterのnameがexplain-doc" grep -qx 'name: explain-doc' "$SKILL/SKILL.md"
check "references/terms.mdがある" test -f "$SKILL/references/terms.md"
check "references/diagrams.mdがある" test -f "$SKILL/references/diagrams.md"
for id in T1 T2 T3 D1 D2 D3 D4; do
  check "自己チェック$idがある" grep -qE "^\| *$id *\|" "$SKILL/SKILL.md"
done
check "descriptionが除外対象を明記する" grep -q 'PR本文' <<<"$FRONT"
check "evals.jsonが正しいJSON" jq -e . "$SKILL/evals/evals.json"
check "evalsのskill_nameが一致" jq -e '.skill_name == "explain-doc"' "$SKILL/evals/evals.json"
check "evalsが3件" jq -e '.evals | length == 3' "$SKILL/evals/evals.json"
check "doc-refineがexplain-docを参照する" grep -q 'explain-doc' "$REFINE"

check "descriptionが状況で書いた発動条件を持つ（流れの説明）" grep -q '流れ' <<<"$FRONT"
check "descriptionが方針のまとめで発動する" grep -q '方針をまとめて' <<<"$FRONT"
check "口頭説明では発動しないと明記する" grep -q 'チャット' <<<"$FRONT"
check "読み手が不明なら既定を置き、質問で止まらない" grep -q '既定' "$SKILL/SKILL.md"
check "doc-refineはhumanizeのD系と衝突しない接頭辞で採番する" grep -q 'E-D1' "$REFINE"
check "doc-refineは用語節がある文書だけにE系を当てる" grep -q '## 用語' "$REFINE"

exit "$fail"
