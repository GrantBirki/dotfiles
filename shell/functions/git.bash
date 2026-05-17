gbr() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "gbr must be run inside a git repository." >&2
        return 1
    fi

    local current_branch=""
    local default_branch=""
    local remote_head=""
    local branch
    local branches_to_delete=()

    current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
        default_branch="${remote_head#origin/}"
    fi

    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        case "$branch" in
            main|master)
                continue
                ;;
        esac

        if [ -n "$default_branch" ] && [ "$branch" = "$default_branch" ]; then
            continue
        fi

        if [ -n "$current_branch" ] && [ "$branch" = "$current_branch" ]; then
            continue
        fi

        branches_to_delete+=("$branch")
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)

    if [ "${#branches_to_delete[@]}" -eq 0 ]; then
        echo "No local branches to delete."
        return 0
    fi

    echo "Deleting local branches:"
    printf "  %s\n" "${branches_to_delete[@]}"
    git branch -D "${branches_to_delete[@]}"
}

gcm() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "gcm must be run inside a git repository." >&2
        return 1
    fi

    local default_branch=""
    local remote_head=""
    remote_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
        default_branch="${remote_head#origin/}"
    fi

    if [ -z "$default_branch" ]; then
        if git show-ref --verify --quiet refs/heads/main || git show-ref --verify --quiet refs/remotes/origin/main; then
            default_branch="main"
        elif git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
            default_branch="master"
        fi
    fi

    if [ -z "$default_branch" ]; then
        echo "Could not determine default branch (tried origin/HEAD, main, master)." >&2
        return 1
    fi

    if [ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" = "$default_branch" ]; then
        echo "Already on $default_branch."
        return 0
    fi

    if git show-ref --verify --quiet "refs/heads/$default_branch"; then
        git switch "$default_branch" 2>/dev/null || git checkout "$default_branch"
        return $?
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
        if git switch --track -c "$default_branch" "origin/$default_branch" 2>/dev/null; then
            return 0
        fi
        git checkout -b "$default_branch" --track "origin/$default_branch"
        return $?
    fi

    echo "Branch $default_branch not found locally or on origin." >&2
    return 1
}
