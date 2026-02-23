# https://github.com/GrantBirki/dotfiles

alias ls='eza --group-directories-first --icons=auto --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias cdc='cd ~/code || cd /mnt/c/code'
alias gbr='git branch | grep -v -E "(master|main)" | xargs git branch -D'
alias gp='git pull'
alias gc='git checkout -b'
alias gpf='git fetch --all && echo -e "\033[1;34m[#]\033[0m Creating Backup Branch: backup-$(git symbolic-ref --short -q HEAD)" && git branch backup-$(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m Force Pull Current Branch from Remote Origin" && git reset --hard origin/$(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m Current Branch is set to state of remote Origin and backup branch created."'
alias lss='eza -lag --time-style=long-iso'
alias h='history | rg -i'
alias dockernuke='docker rm -vf $(docker ps -a -q) && docker rmi -f $(docker images -a -q) && docker system prune -a --volumes'
alias pbcopy='xsel --clipboard --input'
alias pbpaste='xsel --clipboard --output'
alias pss='ps -auxf | head -1 ; ps -auxf | grep -i'
alias ssh="TERM=xterm-256color $(which ssh)"

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
