#!/bin/bash
# setup-dotctl.sh のユニットテスト
#
# **失敗時に既存バイナリを壊さないことが要点。** cron と hook が dotctl 越しに
# 動くようになると、「ビルドが落ちて実行ファイルが消える」は自動化が丸ごと
# 止まる事故になる。テスト失敗・ビルド失敗・起動確認失敗のどれでも、直前まで
# 動いていたバイナリがそのまま残ることを検査する。
#
# go は PATH の stub に差し替える。実ビルドは go test ./... と daily-update が
# 担当で、ここでは分岐だけを速く検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
TARGET="$SCRIPTS_DIR/setup-dotctl.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: $TARGET が存在しません"
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

TEST_DIR=""
BINDIR=""
STUB=""
FAKE_REPO=""

setup() {
  TEST_DIR=$(mktemp -d)
  BINDIR="$TEST_DIR/bin"
  STUB="$TEST_DIR/stub"
  FAKE_REPO="$TEST_DIR/repo"
  mkdir -p "$BINDIR" "$STUB" "$FAKE_REPO/cmd/dotctl"
  git -C "$FAKE_REPO" init -q
  git -C "$FAKE_REPO" config user.email test@example.com
  git -C "$FAKE_REPO" config user.name test
  echo x >"$FAKE_REPO/f"
  git -C "$FAKE_REPO" add -A
  git -C "$FAKE_REPO" commit -qm init
}

teardown() {
  [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# go の stub を作る。$1 が test の終了コード、$2 が build の終了コード。
# build が成功したときは -o の先に「version を答える実行ファイル」を置く。
make_go_stub() {
  local test_rc="$1" build_rc="$2"
  cat >"$STUB/go" <<EOF
#!/bin/bash
if [ -n "\${GO_CWD_LOG:-}" ]; then
  printf '%s %s\n' "\$1" "\$PWD" >>"\$GO_CWD_LOG"
fi
case "\$1" in
  test)  exit $test_rc ;;
  build)
    [ $build_rc -ne 0 ] && exit $build_rc
    out=""
    while [ \$# -gt 0 ]; do
      [ "\$1" = "-o" ] && { out="\$2"; shift; }
      shift
    done
    printf '#!/bin/bash\necho "dotctl stub"\n' >"\$out"
    chmod +x "\$out"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUB/go"
}

# 起動確認で落ちる版（build は成功するが、できたバイナリが非0で返る）
make_go_stub_bad_binary() {
  cat >"$STUB/go" <<'EOF'
#!/bin/bash
case "$1" in
  test) exit 0 ;;
  build)
    out=""
    while [ $# -gt 0 ]; do
      [ "$1" = "-o" ] && { out="$2"; shift; }
      shift
    done
    printf '#!/bin/bash\nexit 9\n' >"$out"
    chmod +x "$out"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUB/go"
}

run_setup() {
  env PATH="$STUB:/usr/bin:/bin" \
    DOTCTL_REPO="$FAKE_REPO" \
    DOTCTL_BIN="$BINDIR/dotctl" \
    bash "$TARGET" "$@" 2>&1
}

# 既に入っているバイナリを置く（壊れないことの検査に使う）
place_existing() {
  printf '#!/bin/bash\necho OLD\n' >"$BINDIR/dotctl"
  chmod +x "$BINDIR/dotctl"
}

check() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
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

has() { grep -q -- "$1" <<<"$2" && echo yes || echo no; }

echo "== 成功経路 =="

setup
make_go_stub 0 0
out=$(run_setup)
rc=$?
check "成功なら 0 で返す" "0" "$rc"
check "バイナリを置く" "yes" "$([ -x "$BINDIR/dotctl" ] && echo yes || echo no)"
check "置いた場所を伝える" "yes" "$(has "$BINDIR/dotctl" "$out")"
teardown

setup
make_go_stub 0 0
place_existing
run_setup >/dev/null
check "既存があれば入れ替える" "dotctl stub" "$("$BINDIR/dotctl")"
teardown

setup
make_go_stub 0 0
# 出力先の親が無くても作る（新環境の ~/.local/bin）
rm -rf "$BINDIR"
run_setup >/dev/null
check "出力先の親ディレクトリを作る" "yes" "$([ -x "$BINDIR/dotctl" ] && echo yes || echo no)"
teardown

echo "== symlink経由のrepo解決 =="

setup
make_go_stub 0 0
mkdir -p "$TEST_DIR/home"
ln -s "$SCRIPTS_DIR" "$TEST_DIR/home/scripts"
# 今回の障害の回帰。~/scripts -> <repo>/scripts のsymlink経由で起動すると、以前は
# scripts/.. を論理pathで辿って$HOMEをrepoと誤認し、go test ./... が失敗していた。
out=$(env PATH="$STUB:/usr/bin:/bin" \
  GO_CWD_LOG="$TEST_DIR/go-cwd.log" \
  DOTCTL_BIN="$BINDIR/dotctl" \
  bash "$TEST_DIR/home/scripts/setup-dotctl.sh" 2>&1)
rc=$?
cwd_log=$(cat "$TEST_DIR/go-cwd.log" 2>/dev/null || true)
check "symlink経由でも成功する" "0" "$rc"
check "testを実repo rootで走らせる" "yes" "$(has "test $REPO_ROOT" "$cwd_log")"
check "buildを実repo rootで走らせる" "yes" "$(has "build $REPO_ROOT" "$cwd_log")"
teardown

echo "== 更新不要ならskip =="

setup
head=$(git -C "$FAKE_REPO" rev-parse HEAD)
# dirtyかどうかではなく、実際にbuildした内容との一致でskipする。
printf 'package dirty\n' >"$FAKE_REPO/dirty.go"
source_hash=$(cd "$FAKE_REPO" && git ls-files -co --exclude-standard -- '*.go' go.mod go.sum | LC_ALL=C sort | while IFS= read -r file; do
  printf '%s\0' "$file"
  git hash-object "$file"
done | git hash-object --stdin)
cat >"$STUB/go" <<'EOF'
#!/bin/bash
if [ "$1" = version ] && [ "${2:-}" = -m ]; then
  printf '%s: go1.27.0\n' "$3"
elif [ "$1" = version ]; then
  echo 'go version go1.27.0 linux/amd64'
else
  echo "UNEXPECTED $*" >>"$GO_CALL_LOG"
  exit 9
fi
EOF
chmod +x "$STUB/go"
cat >"$BINDIR/dotctl" <<EOF
#!/bin/bash
echo 'dotctl $head $source_hash'
EOF
chmod +x "$BINDIR/dotctl"
out=$(GO_CALL_LOG="$TEST_DIR/go.log" run_setup)
rc=$?
check "未commit sourceもbuild済みなら成功する" "0" "$rc"
check "未commit sourceも同じ内容ならtest/buildしない" "0" "$([ -f "$TEST_DIR/go.log" ] && wc -l <"$TEST_DIR/go.log" || echo 0)"
check "skipしたことを伝える" "yes" "$(has 'skipping' "$out")"
teardown

setup
head=$(git -C "$FAKE_REPO" rev-parse HEAD)
source_hash=$(cd "$FAKE_REPO" && git ls-files -co --exclude-standard -- '*.go' go.mod go.sum | LC_ALL=C sort | while IFS= read -r file; do
  printf '%s\0' "$file"
  git hash-object "$file"
done | git hash-object --stdin)
cat >"$STUB/go" <<'EOF'
#!/bin/bash
case "$1" in
  version)
    if [ "${2:-}" = -m ]; then
      printf '%s: go1.26.0\n' "$3"
    else
      echo 'go version go1.27.0 linux/amd64'
    fi
    ;;
  test) exit 0 ;;
  build)
    while [ $# -gt 0 ]; do
      [ "$1" = -o ] && { out="$2"; shift; }
      shift
    done
    printf '#!/bin/bash\necho dotctl rebuilt\n' >"$out"
    chmod +x "$out"
    ;;
esac
EOF
chmod +x "$STUB/go"
cat >"$BINDIR/dotctl" <<EOF
#!/bin/bash
echo 'dotctl $head $source_hash'
EOF
chmod +x "$BINDIR/dotctl"
run_setup >/dev/null
check "commitが同じでもGoが変われば再buildする" "dotctl rebuilt" "$("$BINDIR/dotctl")"
teardown

echo "== go が無いとき =="

setup
# **PATH を削って作らない。** CI の runner は /usr/bin:/bin にも go を持っており、
# それだと go test まで進んでしまい、案内文の検査2件が CI だけ落ちた
out=$(env PATH="$STUB:/usr/bin:/bin" DOTCTL_GO=definitely-not-go \
  DOTCTL_REPO="$FAKE_REPO" DOTCTL_BIN="$BINDIR/dotctl" bash "$TARGET" 2>&1)
rc=$?
check "go が無ければ非0で返す" "1" "$rc"
check "go が要ることを伝える" "yes" "$(has 'go' "$out")"
check "mise を案内する" "yes" "$(has 'mise' "$out")"
teardown

echo "== 失敗経路では既存バイナリを壊さない =="

setup
make_go_stub 1 0
place_existing
out=$(run_setup)
rc=$?
check "テストが落ちたら非0で返す" "1" "$rc"
check "テストが落ちても既存を残す" "OLD" "$("$BINDIR/dotctl")"
check "テスト失敗だと分かる" "yes" "$(has 'テスト' "$out")"
teardown

setup
make_go_stub 0 1
place_existing
out=$(run_setup)
rc=$?
check "ビルドが落ちたら非0で返す" "1" "$rc"
check "ビルドが落ちても既存を残す" "OLD" "$("$BINDIR/dotctl")"
check "ビルド失敗だと分かる" "yes" "$(has 'ビルド' "$out")"
teardown

setup
make_go_stub_bad_binary
place_existing
out=$(run_setup)
rc=$?
check "起動確認で落ちたら非0で返す" "1" "$rc"
check "起動確認で落ちても既存を残す" "OLD" "$("$BINDIR/dotctl")"
teardown

setup
make_go_stub 0 1
# 既存が無い状態でビルドが落ちても、壊れたファイルを置き残さない
out=$(run_setup)
check "失敗時に中間ファイルを残さない" "0" "$(find "$BINDIR" -type f 2>/dev/null | wc -l)"
teardown

echo "== ビルド情報の埋め込み =="

setup
# -ldflags に repo の HEAD と repo パスが入っていること。
# **これが無いと version skew を検知できない**
cat >"$STUB/go" <<'EOF'
#!/bin/bash
case "$1" in
  test) exit 0 ;;
  build)
    printf '%s\n' "$@" >"$LDFLAG_LOG"
    out=""
    while [ $# -gt 0 ]; do
      [ "$1" = "-o" ] && { out="$2"; shift; }
      shift
    done
    printf '#!/bin/bash\necho ok\n' >"$out"
    chmod +x "$out"
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB/go"
head=$(git -C "$FAKE_REPO" rev-parse HEAD)
env PATH="$STUB:/usr/bin:/bin" DOTCTL_REPO="$FAKE_REPO" DOTCTL_BIN="$BINDIR/dotctl" \
  LDFLAG_LOG="$TEST_DIR/ldflags" bash "$TARGET" >/dev/null 2>&1
log=$(cat "$TEST_DIR/ldflags" 2>/dev/null || echo "")
check "commit を埋め込む" "yes" "$(has "$head" "$log")"
check "repo パスを埋め込む" "yes" "$(has "$FAKE_REPO" "$log")"
check "source fingerprintを埋め込む" "yes" "$(has '.SourceHash=' "$log")"
teardown

echo "== テストを飛ばせる（緊急時） =="

setup
make_go_stub 1 0
out=$(run_setup --skip-tests)
rc=$?
check "--skip-tests ならテスト失敗でも通す" "0" "$rc"
check "飛ばしたことを伝える" "yes" "$(has 'skip' "$out")"
teardown

echo
echo "結果: $PASS/$TOTAL passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
