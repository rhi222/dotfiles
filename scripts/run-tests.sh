#!/bin/bash
# tests/<domain>/test-*.sh をまとめて実行する。
#
#   bash scripts/run-tests.sh                        # 全部
#   bash scripts/run-tests.sh --ci                   # `# ci-skip:` を飛ばす（CIから）
#   env TEST_DIR=tests/linear bash scripts/run-tests.sh   # ドメインだけ
#
# 環境変数:
#   TEST_DIR      走査するディレクトリ（既定: リポジトリの tests/）
#                 ドメインを渡せばそこだけ走る（例: TEST_DIR=tests/linear）
#   TEST_TIMEOUT  1本あたりの制限秒（既定: 300）
#   TEST_JOBS     同時実行数（既定: nproc を 16 で打ち止め。1 で直列）
#   TEST_GO       Go テストを走らせるか（既定: TEST_DIR を明示していなければ 1）
#   TEST_GO_REPO  go test を走らせるモジュールのルート（テストで差し替える）
#
# CIで走らせられないテストは、テストファイル側の先頭付近に
#   # ci-skip: <理由>
# と書いて宣言する。除外リストをCI側に置くと、テストを足した人が
# 気付けないまま片方だけ更新されて食い違うため、宣言はテストに持たせる。
#
# ファイル名が test-*.sh に一致しないのは、自分自身を走査対象に含めないため。
#
# 表示名は TEST_DIR からの相対パス。**basename では別ドメインの同名テストを
# 区別できず、どちらが落ちたか分からない**（tests/ を階層に分けた時点で起きる）。
#
# **並列で走らせるが、出力は直列時と同じ**（テスト名の昇順、1本1行、失敗した
# ものだけ出力を見せる）。各テストの出力を個別ファイルへ溜め、全部終わってから
# 順に流す。走っている最中に進捗が出ないのは、混ざった行を読むより結果が
# 揃っているほうが速く読めるため。
#
# 実測（16コア機、55本）: 直列 52秒 -> 並列 9〜36秒。`--ci` では 42秒 -> 約14秒
# （`--ci` は最長の1本が ci-skip で外れるが、残りの本数は変わらない）。
# 並列時のばらつきが大きいので、1回の計測で判断しないこと。
#
# 並列化の前提は「各テストが mktemp で自分の作業場を作る」こと。固定パスへ書く
# テストを足すと隣のテストと踏み合う。/tmp の固定名を値として渡しているだけの
# 箇所（payload の cwd など）は書き込みが無いので問題ない。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 既定はリポジトリの tests/。無ければ従来どおり scripts/ を見る
# （テストの移設前後どちらでも動くようにしておく）
default_test_dir() {
  local t="$SCRIPT_DIR/../tests"
  if [ -d "$t" ]; then (cd "$t" && pwd); else echo "$SCRIPT_DIR"; fi
}
# **ドメイン実行（TEST_DIR=tests/linear）では Go テストを走らせない。**
# 一部だけ走らせたいときに Go のビルドまで動くと驚くため。既定を入れる前に
# 明示されたかを見て、TEST_GO で上書きできるようにする
TEST_GO="${TEST_GO:-$([ -n "${TEST_DIR:-}" ] && echo 0 || echo 1)}"
TEST_DIR="${TEST_DIR:-$(default_test_dir)}"

# Go モジュールのルート（テストで差し替える）
TEST_GO_REPO="${TEST_GO_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"

# 既定の同時実行数。16 で打ち止めにする。
#
# **下限は「最も長い1本」で決まる。** 16コア機での実測（52本）:
#   直列 52秒 / jobs=4 15〜20秒 / jobs=8 約14秒 / jobs=16 9〜13秒 / jobs=24 11〜13秒
# 最長が test-nvim-session-autosave.sh の 9.5秒なので、8 を超えると削れるのは
# 尻尾だけになる。それでも 16 まで取るのは、`--ci`（この最長が ci-skip で外れる）
# だと下限が 4.9秒まで下がり、まだ縮む余地があるため。
default_jobs() {
  local n
  n="$(nproc 2>/dev/null || echo 1)"
  [ "$n" -gt 16 ] && n=16
  [ "$n" -lt 1 ] && n=1
  echo "$n"
}
TEST_JOBS="${TEST_JOBS:-$(default_jobs)}"

CI_MODE=0
[ "${1:-}" = "--ci" ] && CI_MODE=1

# **再帰で拾う。** tests/<domain>/ に分けてあるので直下だけでは0件になる。
# sort はフルパスに対して掛かるので、表示はドメインごとに固まる
mapfile -t tests < <(find "$TEST_DIR" -type f -name 'test-*.sh' | sort)

if [ "${#tests[@]}" -eq 0 ]; then
  echo "テストが1本も見つからない: $TEST_DIR" >&2
  exit 1
fi

WORK="$(mktemp -d -t run-tests.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1本走らせて、結果を $WORK/<idx>.{status,out} に書く。
# 標準出力には何も出さない（呼び出し側が順に流す）。
run_one() {
  local idx="$1" path="$2"
  local out rc
  if out=$(timeout "$TEST_TIMEOUT" bash "$path" 2>&1); then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" >"$WORK/$idx.status"
  printf '%s' "$out" >"$WORK/$idx.out"
}

# 投入。ci-skip の判定は走らせる前に済ませ、スキップは status に 'skip' を書く
# （順に流すときに実行分と同じ枠で扱えるようにするため）。
#
# `# serial:` を宣言したテストは並列の枠に入れず、後で1本ずつ走らせる。
# 負荷で結果が変わる種類（実 nvim を起動して 5000ms のデバウンスを待つ、
# 実 $HOME の設定で対話シェルを起動する）が並列化で flaky になったため。
# ci-skip とは独立した軸で、`--ci` でもこの直列扱いは効く。
serial_idx=()
running=0
for i in "${!tests[@]}"; do
  t="${tests[$i]}"

  # ci-skip / serial の宣言はヘッダにだけ置く
  # （本文中の同名文字列を拾わないよう先頭20行に限る）
  if [ "$CI_MODE" -eq 1 ] && reason=$(head -20 "$t" | grep -m1 -oP '(?<=# ci-skip:).*'); then
    printf 'skip\n' >"$WORK/$i.status"
    printf '%s' "$reason" >"$WORK/$i.out"
    continue
  fi

  if head -20 "$t" | grep -qP '^#\s*serial:'; then
    serial_idx+=("$i")
    continue
  fi

  if [ "$TEST_JOBS" -le 1 ]; then
    run_one "$i" "$t"
    continue
  fi

  run_one "$i" "$t" &
  running=$((running + 1))
  if [ "$running" -ge "$TEST_JOBS" ]; then
    wait -n
    running=$((running - 1))
  fi
done
wait

# 並列分が全部終わってから直列分を1本ずつ。**並列分と重ねない**のが要点で、
# 重ねると「隣で16本走っている間に実 nvim を待つ」状態が再現してしまう。
for i in "${serial_idx[@]+"${serial_idx[@]}"}"; do
  run_one "$i" "${tests[$i]}"
done

passed=0
failed=0
skipped=0
failed_names=()

# Go テストを1回走らせ、**既存の出力契約に畳む**。
#   - パッケージごとに1行（`PASS  go: <pkg>`）
#   - 成功時は go の生出力を出さない。失敗時だけ詳細を見せる
# go test はパッケージを内部で並列に走らせるので、こちらで分割はしない。
go_lines=()
run_go_tests() {
  [ "$TEST_GO" = "1" ] || return 0
  [ -f "$TEST_GO_REPO/go.mod" ] || return 0

  if ! command -v go >/dev/null 2>&1; then
    go_lines+=("skip|go|go が無い（mise で入れる: mise install go）")
    return 0
  fi

  local out rc
  out=$(cd "$TEST_GO_REPO" && go test ./... 2>&1)
  rc=$?

  # `ok  <pkg>  0.01s` / `FAIL <pkg> ...` / `?  <pkg> [no test files]` を拾う。
  # `?` はテストを持たないパッケージなので件数に数えない
  local line pkg
  while IFS= read -r line; do
    case "$line" in
      ok*)
        pkg=$(awk '{print $2}' <<<"$line")
        [ -n "$pkg" ] && go_lines+=("pass|$pkg|")
        ;;
      FAIL*)
        pkg=$(awk '{print $2}' <<<"$line")
        # `FAIL` 単独行（全体のサマリ）はパッケージ名を持たない
        case "$pkg" in "" | *.go*) continue ;; esac
        go_lines+=("fail|$pkg|")
        ;;
    esac
  done <<<"$out"

  # パッケージ行が1つも取れないのにコマンドが落ちたときは、ビルドエラーなどで
  # サマリ形式にならなかった場合。**黙って成功にしない**ため1件として扱う
  if [ "$rc" -ne 0 ] && [ "${#go_lines[@]}" -eq 0 ]; then
    go_lines+=("fail|go build|")
  fi

  GO_OUTPUT="$out"
}
GO_OUTPUT=""
run_go_tests

# 出力。tests は sort 済みなので、添字順に流せば直列時と同じ並びになる
for i in "${!tests[@]}"; do
  name="${tests[$i]#"$TEST_DIR"/}"
  rc="$(cat "$WORK/$i.status" 2>/dev/null || echo 1)"

  if [ "$rc" = "skip" ]; then
    echo "SKIP  $name —$(cat "$WORK/$i.out" 2>/dev/null)"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$rc" = "0" ]; then
    echo "PASS  $name"
    passed=$((passed + 1))
    continue
  fi

  if [ "$rc" = "124" ]; then
    echo "TIMEOUT  $name（${TEST_TIMEOUT}秒で打ち切り）"
  else
    echo "FAIL  $name（exit $rc）"
  fi
  # 失敗したものだけ出力を見せる。全部出すとCIログが読めなくなる。
  # `|| [ -n "$line" ]` は末尾に改行が無いファイルの最終行を落とさないため
  # （テストの出力をそのまま溜めているので、改行で終わらないことがある）
  while IFS= read -r line || [ -n "$line" ]; do
    printf '      | %s\n' "$line"
  done <"$WORK/$i.out"
  failed=$((failed + 1))
  failed_names+=("$name")
done

# Go の結果を同じ体裁で流す
for entry in ${go_lines[@]+"${go_lines[@]}"}; do
  IFS='|' read -r kind pkg reason <<<"$entry"
  case "$kind" in
    pass)
      echo "PASS  go: $pkg"
      passed=$((passed + 1))
      ;;
    skip)
      echo "SKIP  go — $reason"
      skipped=$((skipped + 1))
      ;;
    fail)
      echo "FAIL  go: $pkg"
      failed=$((failed + 1))
      failed_names+=("go:$pkg")
      ;;
  esac
done

# 失敗があったときだけ go の生出力を見せる（1本1行の体裁を崩さないため）
if [ -n "$GO_OUTPUT" ] && printf '%s\n' ${go_lines[@]+"${go_lines[@]}"} | grep -q '^fail|'; then
  while IFS= read -r line || [ -n "$line" ]; do
    printf '      | %s\n' "$line"
  done <<<"$GO_OUTPUT"
fi

echo "---"
echo "pass: $passed 件 / fail: $failed 件 / skip: $skipped 件"

if [ "$failed" -gt 0 ]; then
  echo "失敗: ${failed_names[*]}"
  exit 1
fi
exit 0
