#!/bin/bash
# scripts/worktree/cleanup.sh（互換 wrapper）と dotctl worktree cleanup の出力を比較し、
# あわせて実 git リポジトリに対する掃除の振る舞いを検査する。
#
# **役割は2つ。** wrapper が引数と終了コードをそのまま転送していることの確認と、
# 判定・削除の end-to-end の確認。移植時は Shell 実装との一致検査として使い、
# wrapper へ切り替えた後は転送の検査として同じ形で効き続ける。
#
# **wrapper は $HOME/.local/bin/dotctl を優先するので、HOME を差し替えて
# hermetic にする。** そうしないと「利用者の端末に入っている dotctl が古いか」で
# 結果が変わる（実際に version skew 警告が出て食い違った）。
#
# 実リポジトリを1つ作り、
# locked / detached / dirty / 未追跡のみ / MERGED / CLOSED / OPEN / PR なし /
# PR 取得失敗を1つのリポジトリに揃えて、両方の出力をバイト単位で比べる。
#
# **リポジトリは1つに絞る。** 複数にすると Shell 版のセクション順が find の
# ファイルシステム順（非決定的）になり、Go 版の辞書順と比較できない。
# その差は既知で、docs/worktree.md に「Go 版は決定的」と書いてある。
#
# PR 状態は WORKTREE_CLEANUP_PR_STATE_CMD で差し替える（両実装が同じ口を持つ）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
SHELL_IMPL="$SCRIPTS_DIR/worktree/cleanup.sh"

if [[ ! -f "$SHELL_IMPL" ]]; then
  echo "ERROR: $SHELL_IMPL が存在しません"
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "SKIP: go が無いので比較できない"
  exit 0
fi

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  ok   $name"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $name"
    echo "         expected: $expected"
    echo "         actual  : $actual"
  fi
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# fixture を指定パスに構築する。
#
# **cp -a で複製してはいけない。** worktree の .git ファイルは元リポジトリの
# .git/worktrees/<name> を絶対パスで指すので、コピーすると admin データが
# 元を指したままになり `git worktree remove` が必ず失敗する（実際に踏んだ）。
# 実削除の比較では両方をゼロから作る。
build_fixture() {
  local root="$1"
  local repo="$root/example.com/o/r"
  mkdir -p "$repo"

  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  echo base >"$repo/base.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init

  local name
  for name in merged-clean closed-clean open-one no-pr pr-fails \
    dirty-tracked untracked-only locked-one gone-one; do
    git -C "$repo" worktree add -q -b "$name" "$repo/.wt/$name" >/dev/null 2>&1
  done

  # 追跡ファイルの変更
  echo changed >>"$repo/.wt/dirty-tracked/base.txt"
  # 未追跡のみ
  echo scratch >"$repo/.wt/untracked-only/scratch.txt"
  echo scratch2 >"$repo/.wt/untracked-only/scratch2.txt"
  # locked
  git -C "$repo" worktree lock --reason "claude session" "$repo/.wt/locked-one"
  # detached
  git -C "$repo" worktree add -q --detach "$repo/.wt/detached-one" >/dev/null 2>&1
  # prunable（ディレクトリだけ消す）
  rm -rf "$repo/.wt/gone-one"
}

ROOT="$TEST_DIR/roots"
build_fixture "$ROOT"

# PR 状態のスタブ。ブランチ名から状態を決める
STUB="$TEST_DIR/pr-state.sh"
cat >"$STUB" <<'STUBEOF'
#!/bin/bash
case "$2" in
  merged-clean | dirty-tracked | untracked-only | locked-one) echo "MERGED #1" ;;
  closed-clean) echo "CLOSED #2" ;;
  open-one) echo "OPEN #3" ;;
  no-pr) echo "NONE" ;;
  pr-fails) exit 1 ;;
  *) echo "NONE" ;;
esac
STUBEOF
chmod +x "$STUB"

# Go 版をこのテスト専用にビルドする（~/.local/bin の版に依存しない）
GOBIN="$TEST_DIR/dotctl"
if ! (cd "$REPO_ROOT" && go build -o "$GOBIN" ./cmd/dotctl) 2>"$TEST_DIR/build.err"; then
  echo "ERROR: dotctl のビルドに失敗"
  cat "$TEST_DIR/build.err"
  exit 1
fi

FAKE_HOME="$TEST_DIR/fakehome"
mkdir -p "$FAKE_HOME"

# wrapper 経由。HOME を差し替えて $HOME/.local/bin を空にし、PATH 上の
# テスト用バイナリへ落ちるようにする（wrapper の PATH フォールバックの検査も兼ねる）
run_shell() {
  env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
    WORKTREE_CLEANUP_ROOTS="$ROOT" \
    WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" \
    bash "$SHELL_IMPL" "$@" 2>&1
}

run_go() {
  env WORKTREE_CLEANUP_ROOTS="$ROOT" \
    WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" \
    "$GOBIN" worktree cleanup "$@" 2>&1
}

# 走査ルートは mktemp のパスなので、出力に出る絶対パスを正規化して比べる
normalize() {
  sed -e "s|$ROOT|<ROOT>|g" -e "s|$TEST_DIR|<TMP>|g"
}

compare() {
  local label="$1"
  shift
  run_shell "$@" | normalize >"$TEST_DIR/sh.out"
  run_go "$@" | normalize >"$TEST_DIR/go.out"
  if diff -u "$TEST_DIR/sh.out" "$TEST_DIR/go.out" >"$TEST_DIR/diff.out"; then
    PASS=$((PASS + 1))
    echo "  ok   $label は出力が一致する"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL $label の出力が食い違う"
    sed 's/^/         /' "$TEST_DIR/diff.out"
  fi
}

echo "== dry-run の出力比較 =="
compare "dry-run"
compare "--size"
compare "--force"
compare "--force --size"

echo "== 判定が期待どおりか（両実装で同じ内容を確認） =="
out=$(run_go)
check "MERGED は DELETE" "yes" "$(grep -q '\[DELETE\] merged-clean' <<<"$out" && echo yes || echo no)"
check "CLOSED も DELETE" "yes" "$(grep -q '\[DELETE\] closed-clean' <<<"$out" && echo yes || echo no)"
check "OPEN は KEEP" "yes" "$(grep -qE '\[KEEP  \] open-one .*OPEN #3' <<<"$out" && echo yes || echo no)"
check "PR なしは KEEP" "yes" "$(grep -qE '\[KEEP  \] no-pr .*PR なし' <<<"$out" && echo yes || echo no)"
check "PR 取得失敗は KEEP" "yes" "$(grep -qE '\[KEEP  \] pr-fails .*取得に失敗' <<<"$out" && echo yes || echo no)"
check "追跡変更ありは SKIP" "yes" "$(grep -q '\[SKIP  \] dirty-tracked' <<<"$out" && echo yes || echo no)"
check "未追跡のみは DELETE で件数を併記" "yes" "$(grep -qE '\[DELETE\] untracked-only .*未追跡 2 件あり' <<<"$out" && echo yes || echo no)"
check "locked は SKIP" "yes" "$(grep -qE '\[SKIP  \] locked-one .*locked \(claude session\)' <<<"$out" && echo yes || echo no)"
check "detached は SKIP" "yes" "$(grep -qE '\[SKIP  \] （detached）.*detached HEAD' <<<"$out" && echo yes || echo no)"
check "消えたディレクトリは PRUNE" "yes" "$(grep -q '\[PRUNE \] gone-one' <<<"$out" && echo yes || echo no)"

echo "== --force で locked と detached は消えない =="
out=$(run_go --force)
check "locked は --force でも SKIP" "yes" "$(grep -q '\[SKIP  \] locked-one' <<<"$out" && echo yes || echo no)"
check "detached は --force でも SKIP" "yes" "$(grep -qE '\[SKIP  \] （detached）' <<<"$out" && echo yes || echo no)"
check "dirty は --force で DELETE" "yes" "$(grep -qE '\[DELETE\] dirty-tracked .*破棄されます' <<<"$out" && echo yes || echo no)"

echo "== 実削除（--execute）でも一致する =="

# **実削除は状態を変えるので、両方に独立した fixture を作る**
SH_ROOT="$TEST_DIR/sh-root"
GO_ROOT="$TEST_DIR/go-root"
build_fixture "$SH_ROOT"
build_fixture "$GO_ROOT"

sh_exec=$(env HOME="$FAKE_HOME" PATH="$TEST_DIR:$PATH" \
  WORKTREE_CLEANUP_ROOTS="$SH_ROOT" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" \
  bash "$SHELL_IMPL" --execute 2>&1 | sed -e "s|$SH_ROOT|<ROOT>|g" -e "s|$TEST_DIR|<TMP>|g")
go_exec=$(env WORKTREE_CLEANUP_ROOTS="$GO_ROOT" WORKTREE_CLEANUP_PR_STATE_CMD="$STUB" \
  "$GOBIN" worktree cleanup --execute 2>&1 | sed -e "s|$GO_ROOT|<ROOT>|g" -e "s|$TEST_DIR|<TMP>|g")

check "--execute の出力が一致する" "$sh_exec" "$go_exec"

# 実際に消えたか / 残ったかを確認する
check "MERGED の worktree が消えている" "no" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/merged-clean" ] && echo yes || echo no)"
check "CLOSED の worktree が消えている" "no" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/closed-clean" ] && echo yes || echo no)"
check "未追跡のみの worktree が消えている" "no" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/untracked-only" ] && echo yes || echo no)"
check "locked の worktree は残っている" "yes" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/locked-one" ] && echo yes || echo no)"
check "OPEN の worktree は残っている" "yes" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/open-one" ] && echo yes || echo no)"
check "dirty の worktree は残っている" "yes" \
  "$([ -d "$GO_ROOT/example.com/o/r/.wt/dirty-tracked" ] && echo yes || echo no)"
check "Shell 版も同じ結果になる（消えた側）" "no" \
  "$([ -d "$SH_ROOT/example.com/o/r/.wt/merged-clean" ] && echo yes || echo no)"
check "Shell 版も同じ結果になる（残った側）" "yes" \
  "$([ -d "$SH_ROOT/example.com/o/r/.wt/locked-one" ] && echo yes || echo no)"

echo "== wrapper の契約 =="

# 引数は素通し。知らないオプションは非0で、何が不正だったかを出す
out=$(run_shell --frobnicate 2>&1)
rc=$?
check "知らないオプションは非0で返す" "1" "$rc"
check "何が不正だったか出す" "yes" "$(grep -q 'frobnicate' <<<"$out" && echo yes || echo no)"

# --help は exit 0。**文言は dotctl 側のものになる**（移植後の正しい入口を案内する
# ほうが有用なので、ここだけは意図して一致させていない）
out=$(run_shell --help 2>&1)
rc=$?
check "--help は 0 で返す" "0" "$rc"
check "--help に主要オプションが出る" "yes" \
  "$(grep -q -- '--execute' <<<"$out" && grep -q -- '--force' <<<"$out" && grep -q -- '--size' <<<"$out" && echo yes || echo no)"

# **$HOME/.local/bin を優先する。** cron と hook は最小 PATH で走るので、
# PATH に依存せず引けることが要る
mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\necho HOME_BIN_USED\n' >"$FAKE_HOME/.local/bin/dotctl"
chmod +x "$FAKE_HOME/.local/bin/dotctl"
out=$(run_shell 2>&1)
check "\$HOME/.local/bin の dotctl を優先する" "yes" \
  "$(grep -q 'HOME_BIN_USED' <<<"$out" && echo yes || echo no)"
rm -rf "$FAKE_HOME/.local"

# dotctl がどこにも無ければ、ビルド方法を案内して非0で返す
out=$(env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash "$SHELL_IMPL" 2>&1)
rc=$?
check "dotctl が無ければ非0で返す" "1" "$rc"
check "ビルド方法を案内する" "yes" \
  "$(grep -q 'setup/dotctl.sh' <<<"$out" && echo yes || echo no)"

echo
echo "結果: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
