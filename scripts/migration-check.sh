#!/bin/bash
# 移行前チェック: リポジトリに残るローカル専用の作業状態を洗い出す
#
# PC 移行は「再clone を基本とし、ローカル専用の状態が残るリポジトリだけ tar で運ぶ」
# 方針（docs/migration.md）で、このスクリプトはその3グループ判定の入力を作る。
# 再clone で戻らないもの＝push で逃がすか tar で運ぶ必要があるものだけを報告する。
#
# 使い方:
#   bash scripts/migration-check.sh              # ghq の全リポジトリ + ホーム直下の野良リポジトリ
#   bash scripts/migration-check.sh <dir>...     # 指定ディレクトリだけ（テストもこの経路）
#
# 報告する項目:
#   remote:なし  remote が1つも無い。push で逃がせず、コピーしないと履歴ごと消える
#   unpushed:N   どの remote にも無いコミット数（全ブランチ）
#   stash:N      stash の件数
#   dirty:N      作業ツリーの差分（未追跡を含む）件数
#   worktree:N   併設 worktree の数
#
# 終了コード: 0 = 全リポジトリきれい / 1 = 作業状態が残るリポジトリあり
set -uo pipefail

# 対象リポジトリを1行1パスで出す。引数があればそれを、無ければ ghq と
# ホーム直下（隠しディレクトリ配下は除く）の野良リポジトリを並べる
list_targets() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return 0
  fi
  if ! command -v ghq >/dev/null 2>&1; then
    echo "ERROR: ghq が見つかりません。対象ディレクトリを引数で渡してください" >&2
    return 1
  fi
  ghq list -p
  find "$HOME" -maxdepth 2 -name .git -not -path "$HOME/.*/*" 2>/dev/null |
    while IFS= read -r gitdir; do
      dirname "$gitdir"
    done
}

count_lines() {
  # `wc -l` の先頭空白を落として数値だけ返す
  local n
  n=$(wc -l)
  echo $((n))
}

total=0
found=0

targets=$(list_targets "$@") || exit 2

while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || continue
  total=$((total + 1))

  remotes=$(git -C "$repo" remote 2>/dev/null | count_lines)
  unpushed=$(git -C "$repo" log --branches --not --remotes --oneline 2>/dev/null | count_lines)
  stash=$(git -C "$repo" stash list 2>/dev/null | count_lines)
  dirty=$(git -C "$repo" status --porcelain 2>/dev/null | count_lines)
  worktree=$(git -C "$repo" worktree list 2>/dev/null | tail -n +2 | count_lines)

  if [ "$remotes" -eq 0 ] || [ "$unpushed" -gt 0 ] || [ "$stash" -gt 0 ] ||
    [ "$dirty" -gt 0 ] || [ "$worktree" -gt 0 ]; then
    found=$((found + 1))
    line="== $repo "
    [ "$remotes" -eq 0 ] && line+=" remote:なし"
    line+=" unpushed:$unpushed stash:$stash dirty:$dirty worktree:$worktree"
    echo "$line"
  fi
done <<<"$targets"

echo "---"
echo "$found/$total リポジトリにローカル専用の作業状態がある"
[ "$found" -eq 0 ]
