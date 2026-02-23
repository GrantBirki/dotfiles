# https://github.com/GrantBirki/dotfiles
#
# Alias/function documentation contract:
# - Any user-facing `alias name='...'` added here must be documented in
#   `dotfiles/.aliases.yml` with `name`, `args`, and `description`.
# - Any user-facing bash function that acts like a command (directly callable or
#   used behind an alias) must also be documented in `dotfiles/.aliases.yml` and
#   listed in `ALIASES_TRACKED_FUNCTIONS` below.
# - Internal helper functions should be prefixed with `_` or intentionally
#   omitted from `ALIASES_TRACKED_FUNCTIONS`.
# - After editing this file, run `source dotfiles/.bash_aliases && aliases`.
#   The `aliases` command warns when tracked commands are missing metadata.

alias ls='eza --group-directories-first --color=auto'
alias ll='ls -lah --time-style="+%Y-%m-%d %H:%M:%S" --total-size --octal-permissions --no-permissions'
alias la='ls -A'
alias l='ls'
alias c='clear'
alias cdc='cd ~/code'
alias gbr='git branch | grep -v -E "(master|main)" | xargs git branch -D'
alias gcm='git checkout master 2> /dev/null || echo "master branch not found, trying main"; git checkout main'
alias lss='eza -lag --time-style=long-iso'
alias h='history | rg -i'
alias dockernuke='docker rm -vf $(docker ps -a -q) && docker rmi -f $(docker images -a -q) && docker system prune -a --volumes'
alias pbcopy='xsel --clipboard --input'
alias pbpaste='xsel --clipboard --output'
alias pss='ps -auxf | head -1 ; ps -auxf | grep -i'
alias ssh="TERM=xterm-256color $(which ssh)"

# User-facing bash functions that should always exist in .aliases.yml.
ALIASES_TRACKED_FUNCTIONS=(pg gclone gpull_fn aliases_help aliases)

pg() {
    local use_newest=0
    if [ "$1" = "-n" ] || [ "$1" = "--newest" ]; then
        use_newest=1
        shift
    fi

    if [ -z "$1" ]; then
        echo "Usage: pg [-n|--newest] <value>" >&2
        return 2
    fi

    local query="$*"
    if [ $use_newest -eq 1 ]; then
        echo -e "\033[35m[pgrep ${query}] PID CMD_LINE (case-insensitive, newest only)\033[0m\n"
    else
        echo -e "\033[35m[pgrep ${query}] PID CMD_LINE (case-insensitive)\033[0m\n"
    fi

    local output
    local flags=(-i -f -l -a)
    if [ $use_newest -eq 1 ]; then
        flags+=(-n)
    fi
    output=$(pgrep "${flags[@]}" -- "$query")
    local status=$?

    if [ $status -eq 0 ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            echo "$line"
            echo
        done <<< "$output"
    elif [ $status -eq 1 ]; then
        echo -e "\033[33m[pgrep ${query}] nothing found\033[0m"
    fi

    return $status
}

# if the platform is mac, use the mac aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

OPENAI_MARKER="$HOME/.openai_laptop"
OPENAI_NON_OPENAI_KEY_DEFAULT="${OPENAI_NON_OPENAI_KEY_DEFAULT:-/Users/birki/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/PublicKeys/acf6b2512de58191c13bd9b82aa88451.pub}"

choose_non_openai_key() {
    local key_path
    read -r -p "Path to non-OpenAI Secretive key [$OPENAI_NON_OPENAI_KEY_DEFAULT]: " key_path
    key_path=${key_path:-$OPENAI_NON_OPENAI_KEY_DEFAULT}
    if [ ! -f "$key_path" ]; then
        echo "Key not found at $key_path" >&2
        return 1
    fi
    printf "%s" "$key_path"
}

gclone() {
    if [ -z "$1" ]; then
        echo "Usage: gclone <repo-url> [destination]" >&2
        return 1
    fi

    local repo_url=$1
    shift

    local is_openai="y"
    if [ -f "$OPENAI_MARKER" ]; then
        read -r -p "Is this an OpenAI repo? [Y/n]: " is_openai
        is_openai=${is_openai:-y}
    fi

    local dest_arg="$1"
    local repo_dir=${dest_arg:-$(basename "${repo_url%.git}")}
    local clone_cmd=(git clone "$repo_url")
    if [ -n "$dest_arg" ]; then
        clone_cmd+=("$dest_arg")
    fi

    if [[ $is_openai =~ ^[Yy]$ ]]; then
        "${clone_cmd[@]}"
        return $?
    fi

    local key_path
    key_path=$(choose_non_openai_key) || return 1

    local identity_agent="${SSH_AUTH_SOCK:-$OPENAI_SECRETIVE_SOCKET}"
    local ssh_cmd="ssh -o IdentitiesOnly=yes"
    if [ -n "$identity_agent" ]; then
        ssh_cmd="$ssh_cmd -o IdentityAgent=$identity_agent"
    fi
    ssh_cmd="$ssh_cmd -o IdentityFile=$key_path"

    GIT_SSH_COMMAND="$ssh_cmd" "${clone_cmd[@]}"

    if [ -d "$repo_dir/.git" ]; then
        (cd "$repo_dir" && git config --local core.sshCommand "$ssh_cmd")
    else
        echo "Skipped git config: $repo_dir/.git not found" >&2
    fi
}
alias gcl='gclone'

gpull_fn() {
    local answer="y"
    if [ -f "$OPENAI_MARKER" ]; then
        read -r -p "Is this an OpenAI repo for git pull? [Y/n]: " answer
        answer=${answer:-y}
    fi

    if [[ $answer =~ ^[Yy]$ ]]; then
        git pull "$@"
        return $?
    fi

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "gp must be run inside a git repository." >&2
        return 1
    fi

    local key_path
    key_path=$(choose_non_openai_key) || return 1

    local identity_agent="${SSH_AUTH_SOCK:-$OPENAI_SECRETIVE_SOCKET}"
    local ssh_cmd="ssh -o IdentitiesOnly=yes"
    if [ -n "$identity_agent" ]; then
        ssh_cmd="$ssh_cmd -o IdentityAgent=$identity_agent"
    fi
    ssh_cmd="$ssh_cmd -o IdentityFile=$key_path"

    GIT_SSH_COMMAND="$ssh_cmd" git pull "$@"
    git config --local core.sshCommand "$ssh_cmd"
}

alias gp='git pull'
alias gpull='gpull_fn'
alias gc='gclone'

# Show documented aliases from YAML metadata in a readable format.
_find_aliases_yaml() {
    local source_file="${BASH_SOURCE[0]}"
    local source_dir
    source_dir=$(cd "$(dirname "$source_file")" && pwd)

    local candidate
    local candidates=(
        "$source_dir/.aliases.yml"
        "$HOME/code/dotfiles/dotfiles/.aliases.yml"
        "$HOME/.aliases.yml"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            printf "%s\n" "$candidate"
            return 0
        fi
    done

    return 1
}

_documented_alias_names() {
    local yaml_file="$1"
    awk '
    function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
    }
    function unquote(value) {
        value = trim(value)
        if (value ~ /^".*"$/) {
            return substr(value, 2, length(value) - 2)
        }
        return value
    }
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
        line = unquote(line)
        if (line != "") {
            print line
        }
    }
    ' "$yaml_file"
}

_tracked_alias_commands() {
    alias -p | awk '
    /^alias / {
        line = $0
        sub(/^alias /, "", line)
        sub(/=.*/, "", line)
        if (line != "") {
            print line
        }
    }
    '

    local fn_name
    for fn_name in "${ALIASES_TRACKED_FUNCTIONS[@]}"; do
        if declare -F "$fn_name" >/dev/null 2>&1; then
            printf "%s\n" "$fn_name"
        fi
    done
}

_undocumented_alias_commands() {
    local yaml_file="$1"
    local documented tracked cmd

    documented="$(_documented_alias_names "$yaml_file")"
    tracked="$(_tracked_alias_commands | awk 'NF && !seen[$0]++')"

    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        if ! grep -Fxq "$cmd" <<< "$documented"; then
            printf "%s\n" "$cmd"
        fi
    done <<< "$tracked"
}

aliases_help() {
    local filter="${*:-}"
    local yaml_file
    yaml_file="${ALIASES_METADATA_FILE:-$(_find_aliases_yaml)}"

    if [ -z "$yaml_file" ] || [ ! -f "$yaml_file" ]; then
        echo "Alias metadata file not found. Expected .aliases.yml near .bash_aliases." >&2
        return 1
    fi

    local undocumented
    undocumented="$(_undocumented_alias_commands "$yaml_file")"

    if [ -n "$undocumented" ]; then
        echo ""
        echo "  Tracking Warning"
        echo "  ----------------"
        echo "  The following tracked alias/function commands are missing from metadata:"
        while IFS= read -r missing_name; do
            [ -n "$missing_name" ] || continue
            printf "  - %s\n" "$missing_name"
        done <<< "$undocumented"
        printf "  Add them to: %s\n" "$yaml_file"
    fi

    awk -v filter="$filter" '
    function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
    }
    function unquote(value) {
        value = trim(value)
        if (value ~ /^".*"$/) {
            return substr(value, 2, length(value) - 2)
        }
        return value
    }
    function flush_record(    args_display, haystack) {
        if (name == "") {
            return
        }

        args_display = args
        if (args_display == "" || args_display == "null" || args_display == "~") {
            args_display = "-"
        }

        haystack = tolower(name " " args_display " " description)
        if (filter_lc == "" || index(haystack, filter_lc) > 0) {
            printf "  %-12s %-28s %s\n", name, args_display, description
            shown += 1
        }

        name = ""
        args = ""
        description = ""
    }
    BEGIN {
        filter_lc = tolower(filter)
        shown = 0
        print ""
        print "  Bash Alias + Function Reference"
        print "  -------------------------------"
        if (filter != "") {
            printf "  Filter: %s\n", filter
        }
        printf "  %-12s %-28s %s\n", "COMMAND", "ARGS", "DESCRIPTION"
        printf "  %-12s %-28s %s\n", "-----", "----", "-----------"
    }
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
        flush_record()
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
        name = unquote(line)
        next
    }
    /^[[:space:]]*args:[[:space:]]*/ {
        line = $0
        sub(/^[[:space:]]*args:[[:space:]]*/, "", line)
        args = unquote(line)
        next
    }
    /^[[:space:]]*description:[[:space:]]*/ {
        line = $0
        sub(/^[[:space:]]*description:[[:space:]]*/, "", line)
        description = unquote(line)
        next
    }
    END {
        flush_record()
        if (shown == 0) {
            if (filter != "") {
                printf "  No aliases matched filter: %s\n", filter
            } else {
                print "  No alias metadata entries found."
            }
        }
        print ""
    }
    ' "$yaml_file"
}

aliases() {
    aliases_help "$@"
}

alias aliases='aliases_help'
