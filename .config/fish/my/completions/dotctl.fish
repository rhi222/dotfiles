# dotctl のトップレベルサブコマンド。
# 各候補を分けて定義し、補完メニューに短い説明を表示する。
set -l dotctl_commands \
    worktree \
    settings \
    skill \
    private-bundle \
    wsl \
    doctor \
    docker \
    agent-usage \
    fisher-update \
    rebuild \
    version \
    help

set -l dotctl_needs_command "not __fish_seen_subcommand_from $dotctl_commands"

complete -c dotctl -f -n "$dotctl_needs_command" -a worktree -d 'git worktree の掃除と初期化'
complete -c dotctl -f -n "$dotctl_needs_command" -a settings -d 設定ファイルをコピー同期
complete -c dotctl -f -n "$dotctl_needs_command" -a skill -d 'skill の監査と vendoring'
complete -c dotctl -f -n "$dotctl_needs_command" -a private-bundle -d ローカル設定の集約と運搬
complete -c dotctl -f -n "$dotctl_needs_command" -a wsl -d 'WSL2 のキャッシュ掃除'
complete -c dotctl -f -n "$dotctl_needs_command" -a doctor -d 環境の残骸と移行前チェック
complete -c dotctl -f -n "$dotctl_needs_command" -a docker -d 'Docker の不要リソースを掃除'
complete -c dotctl -f -n "$dotctl_needs_command" -a agent-usage -d 'AI agent のレート上限を表示'
complete -c dotctl -f -n "$dotctl_needs_command" -a fisher-update -d '変更時だけ fish plugin を更新'
complete -c dotctl -f -n "$dotctl_needs_command" -a rebuild -d 'dotctl を再ビルド'
complete -c dotctl -f -n "$dotctl_needs_command" -a version -d ビルド情報を表示
complete -c dotctl -f -n "$dotctl_needs_command" -a help -d 使い方を表示

# 第2階層以降も、次に選ぶサブコマンドがまだ無い位置だけで提示する。
complete -c dotctl -f -n '__fish_seen_subcommand_from worktree; and not __fish_seen_subcommand_from cleanup init' -a cleanup -d '不要な worktree を掃除'
complete -c dotctl -f -n '__fish_seen_subcommand_from worktree; and not __fish_seen_subcommand_from cleanup init' -a init -d 'worktree 作成後の初期化'

complete -c dotctl -f -n '__fish_seen_subcommand_from settings; and not __fish_seen_subcommand_from sync' -a sync -d 設定ファイルをコピー同期
complete -c dotctl -f -n '__fish_seen_subcommand_from settings; and __fish_seen_subcommand_from sync; and not __fish_seen_subcommand_from claude windows' -a claude -d 'Claude settings を同期'
complete -c dotctl -f -n '__fish_seen_subcommand_from settings; and __fish_seen_subcommand_from sync; and not __fish_seen_subcommand_from claude windows' -a windows -d 'Windows settings を同期'
complete -c dotctl -f -n '__fish_seen_subcommand_from claude windows; and not __fish_seen_subcommand_from pull push status' -a pull -d '実ファイルから repo へ取り込む'
complete -c dotctl -f -n '__fish_seen_subcommand_from claude windows; and not __fish_seen_subcommand_from pull push status' -a push -d 'repo から実ファイルへ書き出す'
complete -c dotctl -f -n '__fish_seen_subcommand_from claude windows; and not __fish_seen_subcommand_from pull push status' -a status -d 同期状態を表示

complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and not __fish_seen_subcommand_from audit vendor trusted' -a audit -d 'skill の内容を監査'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and not __fish_seen_subcommand_from audit vendor trusted' -a vendor -d 'vendored skill を管理'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and not __fish_seen_subcommand_from audit vendor trusted' -a trusted -d 'owner の allowlist を確認'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and __fish_seen_subcommand_from vendor; and not __fish_seen_subcommand_from add update status list' -a add -d 'vendored skill を取り込む'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and __fish_seen_subcommand_from vendor; and not __fish_seen_subcommand_from add update status list' -a update -d 'upstream へ追随'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and __fish_seen_subcommand_from vendor; and not __fish_seen_subcommand_from add update status list' -a status -d '取込済み skill を点検'
complete -c dotctl -f -n '__fish_seen_subcommand_from skill; and __fish_seen_subcommand_from vendor; and not __fish_seen_subcommand_from add update status list' -a list -d '取込済み skill を一覧表示'

complete -c dotctl -f -n '__fish_seen_subcommand_from private-bundle; and not __fish_seen_subcommand_from adopt export import status' -a adopt -d 散らばった実体を集約
complete -c dotctl -f -n '__fish_seen_subcommand_from private-bundle; and not __fish_seen_subcommand_from adopt export import status' -a export -d 'ローカル設定を zip に固める'
complete -c dotctl -f -n '__fish_seen_subcommand_from private-bundle; and not __fish_seen_subcommand_from adopt export import status' -a import -d 'zip からローカル設定を展開'
complete -c dotctl -f -n '__fish_seen_subcommand_from private-bundle; and not __fish_seen_subcommand_from adopt export import status' -a status -d 集約状態を表示

complete -c dotctl -f -n '__fish_seen_subcommand_from wsl; and not __fish_seen_subcommand_from cleanup' -a cleanup -d 'WSL2 のキャッシュを掃除'
complete -c dotctl -f -n '__fish_seen_subcommand_from doctor; and not __fish_seen_subcommand_from residue migration' -a residue -d 環境の残骸を検査
complete -c dotctl -f -n '__fish_seen_subcommand_from doctor; and not __fish_seen_subcommand_from residue migration' -a migration -d 移行前チェック

complete -c dotctl -f -n '__fish_seen_subcommand_from docker; and not __fish_seen_subcommand_from clean refresh notice stale' -a clean -d 不要リソースを掃除
complete -c dotctl -f -n '__fish_seen_subcommand_from docker; and not __fish_seen_subcommand_from clean refresh notice stale' -a refresh -d キャッシュだけを更新
complete -c dotctl -f -n '__fish_seen_subcommand_from docker; and not __fish_seen_subcommand_from clean refresh notice stale' -a notice -d キャッシュ済みの通知を表示
complete -c dotctl -f -n '__fish_seen_subcommand_from docker; and not __fish_seen_subcommand_from clean refresh notice stale' -a stale -d キャッシュの期限切れを判定

complete -c dotctl -f -n '__fish_seen_subcommand_from agent-usage; and not __fish_seen_subcommand_from line detail refresh' -a line -d 'tab bar 用の1行を表示'
complete -c dotctl -f -n '__fish_seen_subcommand_from agent-usage; and not __fish_seen_subcommand_from line detail refresh' -a detail -d 詳細を表示
complete -c dotctl -f -n '__fish_seen_subcommand_from agent-usage; and not __fish_seen_subcommand_from line detail refresh' -a refresh -d レート上限を取得して更新
