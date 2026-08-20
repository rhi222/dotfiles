#!/bin/bash
# skill の内容を機械的に検査し、プロンプトインジェクションの疑いがある箇所を
# 段（HIGH / MED / LOW）付きで列挙する。LLM は一切使わない。
#
#   bash scripts/skill-audit.sh [--quiet] <skill-dir>
#
# 終了コードは HIGH が1件以上あれば 1、それ以外は 0。
# **取込の可否はここでは決めない。** 平文で書かれた指示型の injection は grep では
# 拾い切れないので、skill-vendor.sh は audit が 0 でも人の承認を要求する。
#
# 不可視文字の検出に grep -P を使う。バイト列（\xe2\x80[\x8b-\x8f] 等）で書くと
# GNU grep 3.11 と ugrep 7.8.4 で結果が食い違う（ugrep が3件中1件しか拾わない）。
# -P + \x{...} は両実装で一致することを実測で確認している。
#
# バイナリ判定は grep -Iq で行う。file --mime はコードブロックの多い .md を
# application/javascript と判定するため使えない。
set -uo pipefail

QUIET=0
if [ "${1:-}" = "--quiet" ]; then
  QUIET=1
  shift
fi

usage() {
  cat <<'USAGE' >&2
Usage: skill-audit.sh [--quiet] <skill-dir>

  <skill-dir> 配下の全テキストファイルを走査し、疑わしい箇所を
  [LEVEL] path:line 説明 の形式で列挙する。

  --quiet  findings を出さず要約行だけを出す
USAGE
  exit 2
}

[ "$#" -eq 1 ] || usage
ROOT="${1%/}"
if [ ! -d "$ROOT" ]; then
  echo "Error: ディレクトリが見つかりません: $ROOT" >&2
  exit 2
fi

HIGH_COUNT=0
MED_COUNT=0
LOW_COUNT=0

# 外部ホストの許可リスト。skill が参考リンクとして挙げる先はここに集まる。
# ここに無いホストは LOW として報告し、人が判断する。
ALLOWED_HOSTS='github.com raw.githubusercontent.com gist.github.com docs.anthropic.com developer.mozilla.org react.dev nextjs.org nodejs.org www.npmjs.com npmjs.com'

MAX_FILES=100
MAX_BYTES=1048576

# 段|説明|ERE。grep -E で走査する
RULES_ERE=(
  'HIGH|シェル経由のダウンロード実行|(curl|wget)[^|]*\|[[:space:]]*(ba|z|fi)?sh'
  'HIGH|eval による動的実行|(^|[^[:alnum:]_])eval[[:space:]]'
  'HIGH|base64 デコード|base64[[:space:]]+(-d|-D|--decode)'
  'HIGH|機密ファイルへの参照|(~/\.aws|\.aws/credentials|\.ssh/|id_rsa|id_ed25519|\.netrc|\.docker/config\.json|gh auth token|aws_secret_access_key)'
  'HIGH|外部への送信|(curl[^|]*(--data|-d[[:space:]]|-X[[:space:]]*POST)|(^|[^[:alnum:]_])nc[[:space:]]+-|(^|[^[:alnum:]_])scp[[:space:]])'
  'HIGH|破壊的な操作|(rm[[:space:]]+-[a-zA-Z]*[rf]|--no-verify|git[[:space:]]+push[[:space:]]+--force|git[[:space:]]+reset[[:space:]]+--hard)'
  'HIGH|指示の上書きを狙う文言|([Ii]gnore[[:space:]]+(all[[:space:]]+)?(previous|prior|above)|[Dd]isregard[[:space:]]+(the[[:space:]]+)?(previous|prior|above)|system[[:space:]]+prompt)'
  'HIGH|ハーネスのタグを騙る記述|</?(system-reminder|EXTREMELY_IMPORTANT|EXTREMELY-IMPORTANT|IMPORTANT_INSTRUCTIONS)>'
  'MED|.env への言及|(^|[^[:alnum:]])\.env([^[:alnum:]]|$)'
  'MED|設定・フックへの書き込み言及|(settings\.json|CLAUDE\.md|AGENTS\.md|hooks/|\.bashrc|\.zshrc|config\.fish|crontab)'
  'MED|実行ビットの付与|chmod[[:space:]]+(\+x|[0-7]*7[0-7]*)'
)

# 段|説明|PCRE。grep -P で走査する
RULES_PCRE=(
  'MED|不可視・双方向制御文字|[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]'
)

report() {
  local level="$1" path="$2" no="$3" desc="$4" excerpt="$5"
  case "$level" in
    HIGH) HIGH_COUNT=$((HIGH_COUNT + 1)) ;;
    MED) MED_COUNT=$((MED_COUNT + 1)) ;;
    LOW) LOW_COUNT=$((LOW_COUNT + 1)) ;;
  esac
  [ "$QUIET" -eq 1 ] && return 0
  printf '[%s] %s:%s  %s\n' "$level" "$path" "$no" "$desc"
  if [ -n "$excerpt" ]; then
    # 抜粋は現物へ飛ぶ手がかりなので冒頭だけでよい
    printf '        %s\n' "$(printf '%s' "$excerpt" | cut -c1-100)"
  fi
}

# 走査対象のファイルを列挙する。.git と .vendor.json は自分たちの管理データなので除く
all_files() {
  find "$ROOT" -type f ! -path '*/.git/*' ! -name '.vendor.json' -print | sort
}

text_files() {
  local f
  while IFS= read -r f; do
    grep -Iq . "$f" 2>/dev/null && printf '%s\n' "$f"
  done < <(all_files)
}

rel() { printf '%s' "${1#"$ROOT/"}"; }

# grep のオプションを渡して走査する共通処理（-E と -P で共用）
scan_with() {
  local grep_opt="$1" level="$2" desc="$3" pattern="$4"
  local f hit no text
  while IFS= read -r f; do
    while IFS= read -r hit; do
      no="${hit%%:*}"
      text="${hit#*:}"
      report "$level" "$(rel "$f")" "$no" "$desc" "$text"
    done < <(grep -n "$grep_opt" -e "$pattern" "$f" 2>/dev/null)
  done < <(text_files)
}

scan_rules() {
  local rule level desc pattern
  for rule in "${RULES_ERE[@]}"; do
    level="${rule%%|*}"
    desc="${rule#*|}"
    desc="${desc%%|*}"
    pattern="${rule#*|*|}"
    scan_with -E "$level" "$desc" "$pattern"
  done
  for rule in "${RULES_PCRE[@]}"; do
    level="${rule%%|*}"
    desc="${rule#*|}"
    desc="${desc%%|*}"
    pattern="${rule#*|*|}"
    scan_with -P "$level" "$desc" "$pattern"
  done
}

# frontmatter の allowed-tools が広すぎないかを見る。
# 行頭一致で拾う（frontmatter 以外に行頭 allowed-tools: は現れない）
scan_allowed_tools() {
  local f hit no text
  while IFS= read -r f; do
    case "$f" in */SKILL.md) ;; *) continue ;; esac
    while IFS= read -r hit; do
      no="${hit%%:*}"
      text="${hit#*:}"
      case "$text" in
        *'Bash(*)'* | *'allowed-tools: *'* | *WebFetch* | *WebSearch*)
          report MED "$(rel "$f")" "$no" "allowed-tools が広い" "$text"
          ;;
      esac
    done < <(grep -nE '^allowed-tools:' "$f" 2>/dev/null)
  done < <(text_files)
}

# HTML コメントに長文が隠されていないかを見る。
# レンダリングされないので人が読み飛ばす一方、モデルには渡る
scan_html_comments() {
  local f start n
  while IFS= read -r f; do
    while read -r start n; do
      report MED "$(rel "$f")" "$start" "HTML コメント内に長文（${n}行）" ""
    done < <(awk '
      /<!--/ { inc = 1; start = NR; n = 0 }
      inc    { n++ }
      /-->/  { if (inc && n > 3) print start, n; inc = 0 }
    ' "$f" 2>/dev/null)
  done < <(text_files)
}

# 許可リスト外の外部ホストを列挙する。ホストごとに初出の1件だけ報告する
scan_hosts() {
  local f hit no host
  while IFS= read -r f; do
    while IFS= read -r hit; do
      no="${hit%%:*}"
      host="${hit#*:}"
      case " $ALLOWED_HOSTS " in *" $host "*) continue ;; esac
      report LOW "$(rel "$f")" "$no" "許可リスト外の外部ホスト" "$host"
    done < <(grep -noE 'https?://[A-Za-z0-9.-]+' "$f" 2>/dev/null |
      sed -E 's#^([0-9]+):https?://#\1:#' | awk -F: '!seen[$2]++')
  done < <(text_files)
}

# 非テキストファイルは読んでレビューできないので HIGH で報告する
scan_binary() {
  local f
  while IFS= read -r f; do
    [ -s "$f" ] || continue
    grep -Iq . "$f" 2>/dev/null && continue
    report HIGH "$(rel "$f")" 0 "非テキストファイル（レビューできない）" ""
  done < <(all_files)
}

scan_size() {
  local files bytes
  files="$(all_files | wc -l)"
  bytes="$(du -sb "$ROOT" | cut -f1)"
  if [ "$files" -gt "$MAX_FILES" ]; then
    report LOW "." 0 "ファイル数が多い（$files > $MAX_FILES）" ""
  fi
  if [ "$bytes" -gt "$MAX_BYTES" ]; then
    report LOW "." 0 "総バイト数が大きい（$bytes > $MAX_BYTES）" ""
  fi
}

scan_binary
scan_rules
scan_allowed_tools
scan_html_comments
scan_hosts
scan_size

total=$((HIGH_COUNT + MED_COUNT + LOW_COUNT))
[ "$QUIET" -eq 1 ] || echo ""
echo "$total findings ($HIGH_COUNT HIGH, $MED_COUNT MED, $LOW_COUNT LOW)"

if [ "$HIGH_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
