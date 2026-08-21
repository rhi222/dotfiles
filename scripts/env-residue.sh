#!/bin/bash
# 宣言のどこにも属さないのに環境に居座っているものを洗い出す。
#
#   bash scripts/env-residue.sh
#
# 環境変数:
#   ENV_RESIDUE_REPO  判定に使うリポジトリのルート（既定: このスクリプトの1つ上）
#
# **これは「情報提供」で、見つかっても exit 0 する。** 残骸があること自体は
# 壊れている状態ではなく、放置すると事故になりうる状態。daily-update.sh からは
# run_step_soft で呼ぶので、ここで非0を返すと毎日 FAILED 通知が飛び、
# やがて無視されるようになる。
#
# なぜ要るか。次の3つはどのチェックにも掛からなかった。
#   1. 追跡外の ~/.config/fish/functions/fish_user_key_bindings.fish
#      昔の ~/.fzf/install が置いていく。これの有無で Ctrl+R の担当が端末ごとに
#      割れ、履歴一覧の修正が端末をまたぐたび元へ戻っていた
#   2. ~/.fzf/ の古い clone（mise 管理と二重。PATH 順で古い版を掴む）
#   3. 宣言に無い skill の実ディレクトリ。vendoring 移行前に gh skill が入れた
#      実体が残ると safe_link は SKIP するので、Claude は古い版を読み続ける
#
# migration-check.sh は「リポジトリの作業状態」専用で、環境そのものは見ない。
# そこを埋めるのがこのスクリプト。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${ENV_RESIDUE_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"

found=0

report() {
  found=$((found + 1))
  echo "  $1"
  [ -n "${2:-}" ] && echo "      $2"
  return 0
}

# ---- 1. 旧 fzf の置き土産 ----
#
# ~/.fzf は install スクリプト時代の clone。mise が fzf を管理している今は
# 二重で、PATH の並び次第で古い版を掴む端末が出る。~/.fzf.bash は同梱の
# シェル統合で、bash 側から source されていることがある。
# 以降の `~/...` は人が読む表示文なので展開させない（SC2088 は意図どおり）
# shellcheck disable=SC2088
if [ -d "$HOME/.fzf" ]; then
  report "~/.fzf/ が残っています（fzf は mise 管理なので二重）" \
    "撤去: rm -rf ~/.fzf（bash 側で ~/.fzf.bash を source していないか先に確認）"
fi
# shellcheck disable=SC2088
if [ -e "$HOME/.fzf.bash" ]; then
  report "~/.fzf.bash が残っています" \
    "撤去: rm -f ~/.fzf.bash（.bashrc から source していないか先に確認）"
fi

# ---- 2. 追跡外の fish 関数 ----
#
# ~/.config/fish/functions は fisher（プラグイン）の置き場でもあるので、
# 中身を全部残骸とは言えない。除外は2つ。
#
#   - repo の my/functions が同名を持つもの。fish_function_path の先頭に
#     my/functions が入るので影にできており、実害が無い
#   - fisher が入れたもの
#
# **fisher の判定は名前の規約ではなく fisher 自身が持つ一覧で行う。**
# fisher は プラグインごとに universal 変数 `_fisher_<plugin>_files` へ
# インストールしたファイルの絶対パス（`~` 表記）を記録している。
# 「`_` 始まりはプラグイン」という規約で切った初版は、tide の `fish_prompt` /
# `fish_mode_prompt` / `tide`、fisher 本体の `fisher`、fzf.fish の
# `fzf_configure_bindings` を誤検知した（実環境で5件）。公開関数は普通の名前を持つ。
#
# 一覧が引けない環境（fish 未導入、universal 変数が空）では `_` 始まりの除外に
# 落とす。誤検知が出るのは「fisher の公開関数」だけなので、報告漏れより誤検知の
# ほうがましだが、そもそも fish が無ければ fish 関数の残骸も問題にならない。
live_fish_functions="$HOME/.config/fish/functions"
repo_fish_functions="$REPO/.config/fish/my/functions"

fisher_files() {
  if [ -n "${ENV_RESIDUE_FISHER_FILES:-}" ]; then
    cat "$ENV_RESIDUE_FISHER_FILES" 2>/dev/null
    return 0
  fi
  command -v fish >/dev/null 2>&1 || return 0
  # `~` 表記で記録されているので展開する。string replace は fish 側で行う
  fish -c 'for v in (set -n | string match "_fisher_*_files")
             for f in $$v
               string replace -- "~" $HOME $f
             end
           end' 2>/dev/null
}

if [ -d "$live_fish_functions" ]; then
  managed=" "
  while IFS= read -r f; do
    [ -n "$f" ] && managed="$managed$(basename "$f") "
  done < <(fisher_files)

  # 一覧が空なら fisher の記録が引けなかったということ。名前の規約に落ちる
  fisher_known=0
  [ "$managed" != " " ] && fisher_known=1

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    [ -e "$repo_fish_functions/$base" ] && continue
    if [ "$fisher_known" -eq 1 ]; then
      [[ "$managed" == *" $base "* ]] && continue
    else
      case "$base" in _*) continue ;; esac
    fi
    report "追跡外の fish 関数: ~/.config/fish/functions/$base" \
      "repo の .config/fish/my/functions/ にも fisher の管理下にもありません"
  done < <(find "$live_fish_functions" -maxdepth 1 -type f -name '*.fish' 2>/dev/null | sort)
fi

# ---- 3. 宣言に無い skill ----
#
# 宣言は3つある。trusted（claude-skills.txt / gh が入れた実ディレクトリが正）、
# vendored（skills-vendor/ → symlink が正）、自作（skills/ → symlink が正）。
#
# **宣言が読めないときは skill の判定を丸ごと諦める。** 読めないまま
# 「宣言に無い」と言うと、正しく入っているものまで残骸に見えてしまう。
skills_decl="$REPO/scripts/claude-skills.txt"
if [ ! -f "$skills_decl" ]; then
  echo "  skill の宣言が読めないため skill の判定はしません: $skills_decl"
else
  declared=" "
  while IFS= read -r line; do
    line="${line%%#*}"
    # shellcheck disable=SC2086  # 意図的な単語分割で <owner/repo> <skill> を取る
    set -- $line
    [ "$#" -ge 2 ] || continue
    name="${2%@*}"
    declared="$declared${name} "
  done <"$skills_decl"

  for d in "$REPO/.config/claude/skills" "$REPO/.config/claude/skills-vendor"; do
    [ -d "$d" ] || continue
    while IFS= read -r sub; do
      [ -n "$sub" ] && declared="$declared$(basename "$sub") "
    done < <(find "$d" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done

  # vendored は symlink で入るのが正。実ディレクトリなら古い実体が居座っている
  vendored=" "
  if [ -d "$REPO/.config/claude/skills-vendor" ]; then
    while IFS= read -r sub; do
      [ -n "$sub" ] && vendored="$vendored$(basename "$sub") "
    done < <(find "$REPO/.config/claude/skills-vendor" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  fi

  for live in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do
    [ -d "$live" ] || continue
    while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      name="$(basename "$sub")"
      # codex 同梱の .system 以下は宣言の対象外
      case "$name" in .*) continue ;; esac
      short="${live#"$HOME"/}"

      if [[ "$vendored" == *" $name "* ]]; then
        # 宣言はあるが実ディレクトリ。symlink が張れていない状態
        report "vendored なのに実ディレクトリ: ~/$short/$name" \
          "古い gh 版が読まれています。退避してから ./dotfilesLink.sh"
        continue
      fi
      if [[ "$declared" == *" $name "* ]]; then
        continue
      fi
      report "宣言に無い skill: ~/$short/$name" \
        "trusted なら scripts/claude-skills.txt に、そうでなければ skill-vendor.sh add へ"
    done < <(find "$live" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
  done
fi

if [ "$found" -eq 0 ]; then
  echo "残骸は見つかりませんでした"
fi

# 機械可読サマリ。表示の体裁を変えても呼び出し側が壊れないようにする
echo "env-residue: FOUND=$found"
exit 0
