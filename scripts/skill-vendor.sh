#!/bin/bash
# vendored skill の取込と点検。
#
#   bash scripts/skill-vendor.sh add <owner/repo|git-url> <sub-path> [name]
#   bash scripts/skill-vendor.sh update <name>
#   bash scripts/skill-vendor.sh status [--no-network]
#   bash scripts/skill-vendor.sh list
#
# 個人提供など、信頼済み owner でない skill はここで取り込む。gh skill install を
# 使わないのは、更新のレビュー面を git 差分に一本化するため。実体をコミットして
# あれば、作業ツリーの変更を人が見ずにコミットすることはない。
#
# 取込先は既定で <repo>/.config/claude/skills-vendor。dotfilesLink.sh が
# ~/.claude/skills と ~/.agents/skills へ symlink するので、**作業ツリーを
# 書き換えた瞬間に有効になる**。だから update は必ず人の承認を挟む。
#
# Env:
#   SKILL_VENDOR_DIR         取込先（既定 <repo>/.config/claude/skills-vendor）
#   SKILL_VENDOR_CACHE       clone のキャッシュ（既定 ~/.cache/claude-skills-vendor）
#   SKILL_VENDOR_SELF_SKILLS 自作 skill の場所（既定 <repo>/.config/claude/skills）
#   SKILL_VENDOR_YES=1       承認プロンプトを自動 yes（テスト専用）
#   SKILL_VENDOR_DATE        vendored_at に入れる日付（テスト専用）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$SCRIPT_DIR/skill-audit.sh"

# shellcheck source=lib/text-file.sh
source "$SCRIPT_DIR/lib/text-file.sh"

VENDOR_DIR="${SKILL_VENDOR_DIR:-$REPO_ROOT/.config/claude/skills-vendor}"
CACHE_DIR="${SKILL_VENDOR_CACHE:-$HOME/.cache/claude-skills-vendor}"
SELF_SKILLS="${SKILL_VENDOR_SELF_SKILLS:-$REPO_ROOT/.config/claude/skills}"

usage() {
  cat <<'USAGE' >&2
Usage:
  skill-vendor.sh add <owner/repo|git-url> <sub-path> [name]
  skill-vendor.sh update <name>
  skill-vendor.sh status [--no-network]
  skill-vendor.sh list

  <sub-path> はリポジトリ内の skill ディレクトリ。直下にある場合は "." を渡す。
  [name] を省略すると <sub-path> の basename（"." のときはリポジトリ名）を使う。
USAGE
  exit 2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  if [ "${SKILL_VENDOR_YES:-0}" = "1" ]; then
    echo "$prompt -> 自動承認 (SKILL_VENDOR_YES=1)"
    return 0
  fi
  local ans
  if ! read -r -p "$prompt [y/N] " ans </dev/tty; then
    return 1
  fi
  case "$ans" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

today() { echo "${SKILL_VENDOR_DATE:-$(date +%Y-%m-%d)}"; }

# owner/repo 形式なら GitHub の URL に組み立てる。それ以外は git URL としてそのまま使う。
# 先頭が / ./ ../ のものはローカルパス。テストが git init --bare したローカルディレクトリを
# origin にする（ネットワークに出ないため）ので、owner/repo と誤認させずに素通しする
resolve_origin() {
  local spec="$1"
  case "$spec" in
    /* | ./* | ../* | *://* | *@*:*) printf '%s' "$spec" ;;
    */*) printf 'https://github.com/%s.git' "$spec" ;;
    *) die "owner/repo か git URL を渡してください: $spec" ;;
  esac
}

cache_path() {
  local origin="$1" slug
  slug="$(printf '%s' "$origin" | sed -e 's|^https\?://||' -e 's|^git@||' -e 's|:|/|' -e 's|\.git$||' -e 's|[^A-Za-z0-9._-]|__|g')"
  printf '%s/%s' "$CACHE_DIR" "$slug"
}

# clone か fetch で最新にして、clone 先のパスを返す
clone_or_fetch() {
  local origin="$1" dir
  dir="$(cache_path "$origin")"
  mkdir -p "$CACHE_DIR"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --quiet --depth 1 origin HEAD || return 1
    git -C "$dir" reset --quiet --hard FETCH_HEAD || return 1
  else
    git clone --quiet --depth 1 "$origin" "$dir" || return 1
  fi
  printf '%s' "$dir"
}

# vendored な skill が実際に有効になっているかを見る。
#
# **preflight は add のときだけ走るので、取込後にここを見る場所が無かった。**
# gh skill が先に入れた実ディレクトリが残っていると safe_link は SKIP するので
# symlink が張られず、Claude は古い gh 版を読み続ける。それでも .vendor.json は
# 正しいので status は [OK] を返していた（実際に6本がこの状態だった）。
#
# 無いことは異常ではない（dotfilesLink.sh 未実行、その agent を使っていない端末）。
check_live_dirs() {
  local name="$1" rc=0 live target
  for live in "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name" "$HOME/.agents/skills/$name"; do
    if [ -L "$live" ]; then
      target="$(readlink -f "$live")"
      if [ "$target" != "$(readlink -f "$VENDOR_DIR/$name")" ]; then
        echo "[NG] $name: $live が vendored を指していません（-> $target）"
        rc=1
      fi
    elif [ -d "$live" ]; then
      echo "[NG] $name: $live が実ディレクトリです（vendored が読まれていません）"
      echo "     復旧: その実体を退避してから ./dotfilesLink.sh"
      rc=1
    fi
  done
  return "$rc"
}

# 取込前の門前払い。ここを通ってからでないと1バイトもコピーしない
preflight() {
  local src="$1" name="$2" bin
  [ -f "$src/SKILL.md" ] || die "SKILL.md が見つかりません: $src"

  if [ -d "$SELF_SKILLS/$name" ]; then
    die "自作 skill と名前が衝突しています: $SELF_SKILLS/$name"
  fi

  local live
  for live in "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name" "$HOME/.agents/skills/$name"; do
    if [ -d "$live" ] && [ ! -L "$live" ]; then
      cat >&2 <<MSG
Error: $live が実ディレクトリとして存在します
  gh skill が入れた実体が残っていると symlink が張れず、古い実体が読まれ続けます。
  先に消してください:
    rm -rf ~/.claude/skills/$name ~/.codex/skills/$name ~/.agents/skills/$name
MSG
      exit 1
    fi
  done

  # 非テキストファイルは読んでレビューできないので入れない。
  # 判定は lib/text-file.sh に集約している（skill-audit.sh と一致させるため）
  bin=""
  while IFS= read -r f; do
    is_binary_file "$f" && bin="$bin  ${f#"$src/"}"$'\n'
  done < <(find "$src" -type f ! -path '*/.git/*' -print | sort)
  if [ -n "$bin" ]; then
    echo "Error: 非テキストファイルが含まれています（レビューできないため取り込みません）" >&2
    printf '%s' "$bin" >&2
    exit 1
  fi
}

# src の内容を dest へ置き換える。.git は持ち込まず、実行ビットは落とす
install_files() {
  local src="$1" dest="$2"
  rm -rf "$dest"
  mkdir -p "$dest"
  (cd "$src" && tar cf - --exclude=.git .) | (cd "$dest" && tar xf -) || die "コピーに失敗しました"
  find "$dest" -type f -exec chmod a-x {} + 2>/dev/null
  find "$dest" -type d -exec chmod 755 {} + 2>/dev/null
}

# upstream 側のライセンスを同梱する。skill 直下に無ければリポジトリ直下から拾う
copy_license() {
  local clone="$1" src="$2" dest="$3" f
  for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
    if [ -f "$src/$f" ]; then return 0; fi
  done
  for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
    if [ -f "$clone/$f" ]; then
      cp "$clone/$f" "$dest/LICENSE"
      chmod a-x "$dest/LICENSE"
      return 0
    fi
  done
  echo "[WARN] upstream に LICENSE が見つかりませんでした" >&2
}

detect_license() {
  local dest="$1" f
  for f in "$dest/LICENSE" "$dest/LICENSE.md" "$dest/LICENSE.txt" "$dest/COPYING"; do
    [ -f "$f" ] || continue
    if grep -qi 'MIT License' "$f"; then
      printf 'MIT'
      return 0
    fi
    if grep -qi 'Apache License' "$f"; then
      printf 'Apache-2.0'
      return 0
    fi
    if grep -qi 'GNU GENERAL PUBLIC' "$f"; then
      printf 'GPL'
      return 0
    fi
    printf 'unknown'
    return 0
  done
  printf 'none'
}

write_vendor_json() {
  local dest="$1" origin="$2" sub_path="$3" commit="$4" high="$5" med="$6" low="$7"
  jq -n \
    --arg origin "$origin" \
    --arg sub_path "$sub_path" \
    --arg commit "$commit" \
    --arg vendored_at "$(today)" \
    --arg license "$(detect_license "$dest")" \
    --argjson high "$high" --argjson med "$med" --argjson low "$low" \
    '{
      origin: $origin,
      sub_path: $sub_path,
      commit: $commit,
      vendored_at: $vendored_at,
      reviewed_commit: $commit,
      audit: { high: $high, med: $med, low: $low },
      license: $license
    }' >"$dest/.vendor.json"
}

# audit を走らせて findings を表示し、H/M/L の件数を "H M L" で返す。
# 人向けの findings は stderr へ回す。stdout に混ぜると呼び出し側の
# read が先頭行（findings 側）を読んでしまい、件数が空になる
run_audit() {
  local dir="$1" summary
  bash "$AUDIT" "$dir" >&2
  summary="$(bash "$AUDIT" --quiet "$dir" | tail -1)"
  printf '%s' "$summary" | sed -E 's/^[0-9]+ findings \(([0-9]+) HIGH, ([0-9]+) MED, ([0-9]+) LOW\)$/\1 \2 \3/'
}

cmd_add() {
  [ "$#" -ge 2 ] || usage
  local spec="$1" sub_path="$2" name="${3:-}"
  local origin clone src
  origin="$(resolve_origin "$spec")"

  clone="$(clone_or_fetch "$origin")" || die "clone/fetch に失敗しました: $origin"
  if [ "$sub_path" = "." ]; then
    src="$clone"
    [ -n "$name" ] || name="$(basename "$origin" .git)"
  else
    src="$clone/$sub_path"
    [ -n "$name" ] || name="$(basename "$sub_path")"
  fi

  preflight "$src" "$name"

  local commit
  commit="$(git -C "$clone" rev-parse HEAD)"

  echo "=== audit: $name ($origin @ ${commit:0:7}) ==="
  local counts high med low
  counts="$(run_audit "$src")"
  read -r high med low <<<"$counts"
  echo ""

  if ! confirm "この内容で取り込みますか？（HIGH=$high MED=$med LOW=$low。findings が 0 でも本文は目で読んでください）"; then
    echo "取り込みを中止しました"
    exit 1
  fi

  local dest="$VENDOR_DIR/$name"
  mkdir -p "$VENDOR_DIR"
  install_files "$src" "$dest"
  copy_license "$clone" "$src" "$dest"
  write_vendor_json "$dest" "$origin" "$sub_path" "$commit" "$high" "$med" "$low"

  echo "-> 取り込みました: $dest"
  echo "   次: ./dotfilesLink.sh でリンクを張り、git diff を見てコミットする"
}

cmd_update() {
  [ "$#" -eq 1 ] || usage
  local name="$1"
  local dest="$VENDOR_DIR/$name"
  local json="$dest/.vendor.json"
  [ -f "$json" ] || die "vendored skill が見つかりません: $name"

  local origin sub_path old_commit clone src
  origin="$(jq -r .origin "$json")"
  sub_path="$(jq -r .sub_path "$json")"
  old_commit="$(jq -r .commit "$json")"

  clone="$(clone_or_fetch "$origin")" || die "clone/fetch に失敗しました: $origin"
  if [ "$sub_path" = "." ]; then src="$clone"; else src="$clone/$sub_path"; fi
  [ -d "$src" ] || die "upstream から $sub_path が消えています: $origin"

  local commit
  commit="$(git -C "$clone" rev-parse HEAD)"

  # 置き換え候補を add と同じ手順で一時ディレクトリに組み立ててから diff を取る。
  # dest には copy_license がリポジトリ直下から持ってきた LICENSE が入っている一方、
  # upstream の skill サブディレクトリにはそれが無い。src と直接比べると常に
  # 「LICENSE だけが違う」差分になり、「変更なし」の判定が死ぬ。
  # 置き換える前に diff を取るのは、未レビューの状態を作業ツリーに作らないため
  local staged
  staged="$(mktemp -d)"
  trap 'rm -rf "$staged"' EXIT
  install_files "$src" "$staged/$name"
  copy_license "$clone" "$src" "$staged/$name"

  local diff_out
  diff_out="$(diff -ru -x .git -x .vendor.json "$dest" "$staged/$name" 2>/dev/null)"

  if [ -z "$diff_out" ]; then
    echo "変更なし: $name のファイルは upstream と同一です（${old_commit:0:7} -> ${commit:0:7} はこの skill 以外の変更）"
    local tmp
    tmp="$(mktemp)"
    jq --arg c "$commit" --arg d "$(today)" \
      '.commit = $c | .reviewed_commit = $c | .vendored_at = $d' "$json" >"$tmp" && mv "$tmp" "$json"
    echo "-> commit と reviewed_commit を ${commit:0:7} に更新しました"
    return 0
  fi

  echo "=== diff: $name (${old_commit:0:7} -> ${commit:0:7}) ==="
  printf '%s\n' "$diff_out"
  echo ""
  echo "=== audit: $name (upstream の新しい内容) ==="
  local counts high med low
  counts="$(run_audit "$src")"
  read -r high med low <<<"$counts"
  echo ""

  if ! confirm "この差分を取り込みますか？（HIGH=$high MED=$med LOW=$low）"; then
    echo "取り込みを中止しました（$name は ${old_commit:0:7} のままです）"
    exit 1
  fi

  install_files "$src" "$dest"
  copy_license "$clone" "$src" "$dest"
  write_vendor_json "$dest" "$origin" "$sub_path" "$commit" "$high" "$med" "$low"
  echo "-> 更新しました: $dest"
  echo "   次: git diff を見てコミットする"
}

cmd_status() {
  local no_network=0
  [ "${1:-}" = "--no-network" ] && no_network=1

  if [ ! -d "$VENDOR_DIR" ]; then
    echo "vendored skill はありません（$VENDOR_DIR が無い）"
    return 0
  fi

  local rc=0 found=0 d name json commit reviewed high remote
  for d in "$VENDOR_DIR"/*/; do
    [ -d "$d" ] || continue
    found=1
    name="$(basename "$d")"
    json="$d/.vendor.json"
    if [ ! -f "$json" ]; then
      echo "[NG] $name: .vendor.json が無い"
      rc=1
      continue
    fi
    commit="$(jq -r .commit "$json")"
    reviewed="$(jq -r .reviewed_commit "$json")"
    if [ "$commit" != "$reviewed" ]; then
      echo "[NG] $name: 未レビュー（commit=${commit:0:7} reviewed=${reviewed:0:7}）"
      rc=1
    fi
    high="$(bash "$AUDIT" --quiet "$d" | tail -1 | sed -E 's/^.*\(([0-9]+) HIGH.*$/\1/')"
    if [ "$high" != "0" ]; then
      echo "[NG] $name: audit に HIGH が $high 件ある"
      rc=1
    fi
    if [ "$no_network" -eq 0 ]; then
      remote="$(git ls-remote "$(jq -r .origin "$json")" HEAD 2>/dev/null | awk '{print $1}')"
      if [ -n "$remote" ] && [ "$remote" != "$commit" ]; then
        echo "[--] $name: upstream の HEAD が違う（${commit:0:7} -> ${remote:0:7}）"
        echo "     確認: bash scripts/skill-vendor.sh update $name"
      fi
    fi
    local live_ok=1
    check_live_dirs "$name" || {
      live_ok=0
      rc=1
    }
    if [ "$commit" = "$reviewed" ] && [ "$high" = "0" ] && [ "$live_ok" = "1" ]; then
      echo "[OK] $name (${commit:0:7}, reviewed $(jq -r .vendored_at "$json"))"
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "vendored skill はありません"
  fi
  return "$rc"
}

cmd_list() {
  if [ ! -d "$VENDOR_DIR" ]; then
    echo "vendored skill はありません"
    return 0
  fi
  local d name json
  printf '%-32s %-10s %-12s %s\n' NAME LICENSE VENDORED_AT ORIGIN
  for d in "$VENDOR_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    json="$d/.vendor.json"
    if [ -f "$json" ]; then
      printf '%-32s %-10s %-12s %s\n' \
        "$name" "$(jq -r .license "$json")" "$(jq -r .vendored_at "$json")" "$(jq -r .origin "$json")"
    else
      printf '%-32s %-10s %-12s %s\n' "$name" '?' '?' '(.vendor.json が無い)'
    fi
  done
}

[ -f "$AUDIT" ] || die "skill-audit.sh が見つかりません: $AUDIT"
[ "$#" -ge 1 ] || usage

cmd="$1"
shift
case "$cmd" in
  add) cmd_add "$@" ;;
  update) cmd_update "$@" ;;
  status) cmd_status "$@" ;;
  list) cmd_list "$@" ;;
  *) usage ;;
esac
