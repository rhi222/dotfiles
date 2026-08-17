#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash)
#
# `gh pr create --base <既定ブランチ以外>` を検出して permissionDecision:ask で割り込む。
#
# なぜ必要か: stacked PR は `gh-stack` を使うという規約が rules/pull-request.md と
# wt-pr skill に書いてあるが、どちらも「宣言文」で、手が動く瞬間のチェックではない。
# 規約を読む時点と `gh pr create` を打つ時点の間に実装・コミット分割・push が挟まるため、
# 散文のままでは確率的に見落とされる。判定できる唯一の瞬間がこの base 指定なので、
# ここに機械的なゲートを置く。
#
# deny ではなく ask にしている理由: backport-pr skill は正当に非デフォルト base の PR を
# 作る。deny だとそれが詰まる。ask なら理由文が人間とモデルの両方に見え、人間が判断できる。
#
# 判定は「素通し」に倒す。PR 作成を hook が壊すほうが、規約の取りこぼしより害が大きい。
# jq 不在・壊れた JSON・git リポジトリ外は、いずれも黙って通す。
set -uo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$tool" ] || [ "$tool" = "Bash" ] || exit 0

# `gh pr create` 以外は見ない。`gh stack ...`（gh-stack 本体）や `gh pr list --base` を
# 巻き込まないよう、サブコマンドまで含めて一致させる
printf '%s' "$cmd" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+create\b' || exit 0

# --base / -B / --base=... のいずれか。指定が無ければ gh が既定ブランチを使うので対象外
base=$(printf '%s' "$cmd" | grep -oP '(?:--base|-B)(?:=|\s+)\K[^\s]+' | head -1)
[ -n "$base" ] || exit 0
base=${base#\"}
base=${base%\"}
base=${base#\'}
base=${base%\'}
base=${base#origin/}
[ -n "$base" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$cwd" ]; then
  cwd="$PWD"
elif [ ! -d "$cwd" ]; then
  # cwd の指定はあるのに実在しない。PWD へ落とすと無関係なリポジトリで判定してしまう
  exit 0
fi

git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 既定ブランチはローカルだけで解決する（PR 作成のたびに走るのでネットワークに出ない）
default=$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
[ -n "$default" ] || default=$(git -C "$cwd" config init.defaultBranch 2>/dev/null)
[ -n "$default" ] || default="main"

[ "$base" = "$default" ] && exit 0

reason="base が \"$base\" で、既定ブランチ \"$default\" ではありません。
stacked PR なら rules/pull-request.md の規約により gh-stack skill を使ってください（手作業で --base を積まない）。
意図的な backport（backport-pr skill）であれば承認してください。"

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
