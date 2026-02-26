function open-pr --description "Open pull request page in browser via gh"
    if not type -q gh
        echo "open-pr: gh command not found" >&2
        return 1
    end

    if test (count $argv) -gt 0
        gh pr view --web $argv
        return $status
    end

    # Fast path: let gh resolve PR from current branch.
    gh pr view --web >/dev/null 2>&1
    if test $status -eq 0
        return 0
    end

    set -l branch (git branch --show-current 2>/dev/null)
    if test -z "$branch"
        echo "open-pr: could not detect current branch" >&2
        return 1
    end

    # Fallback for worktree/fork cases where gh cannot map branch -> PR.
    set -l pr_url (gh pr list --head "$branch" --state open --json url --jq '.[0].url' 2>/dev/null)
    if test -n "$pr_url"; and test "$pr_url" != null
        gh browse "$pr_url"
        return $status
    end

    set pr_url (gh pr list --state open --search "head:$branch" --json url --jq '.[0].url' 2>/dev/null)
    if test -n "$pr_url"; and test "$pr_url" != null
        gh browse "$pr_url"
        return $status
    end

    set -l owner (gh repo view --json nameWithOwner --jq '.nameWithOwner | split("/")[0]' 2>/dev/null)
    if test -n "$owner"; and test "$owner" != null
        set pr_url (gh pr list --state open --search "head:$owner:$branch" --json url --jq '.[0].url' 2>/dev/null)
        if test -n "$pr_url"; and test "$pr_url" != null
            gh browse "$pr_url"
            return $status
        end
    end

    echo "open-pr: no open pull request found for branch '$branch'" >&2
    gh pr list --web 2>/dev/null
    return 1
end
