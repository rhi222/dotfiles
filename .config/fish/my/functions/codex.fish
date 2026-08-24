function codex --description 'Codex CLIをrepository単位のaccount homeで起動する'
    set -l repo_root (command git rev-parse --show-toplevel 2>/dev/null)
    if test $status -eq 0
        set repo_root (path resolve -- $repo_root)

        for configured_root in $codex_alt_repo_roots
            if test "$repo_root" = (path resolve -- $configured_root)
                if not set -q codex_alt_home[1]; or test -z "$codex_alt_home"
                    echo 'codex: 対象repositoryだが codex_alt_home が未設定です。通常accountへのfallbackを拒否します。' >&2
                    return 2
                end

                set -lx CODEX_HOME $codex_alt_home
                command codex $argv
                return $status
            end
        end
    end

    command codex $argv
end
