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
alias celar='clear'
alias cdc='cd ~/code'
alias lss='eza -lag --time-style=long-iso'
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

# User-facing bash functions that should always exist in .aliases.yml.
ALIASES_TRACKED_FUNCTIONS=(h gbr gcm dockernuke pg ssh gclone gpull_fn aliases_help aliases)

h() {
    if [ "$#" -eq 0 ]; then
        history
        return $?
    fi

    history | rg -i -- "$*"
}

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

dockernuke() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found." >&2
        return 127
    fi

    local status=0
    local container_ids
    local image_ids

    container_ids=$(docker ps -a -q)
    if [ -n "$container_ids" ]; then
        docker rm -vf $container_ids || status=$?
    else
        echo "No Docker containers to remove."
    fi

    image_ids=$(docker images -a -q)
    if [ -n "$image_ids" ]; then
        docker rmi -f $image_ids || status=$?
    else
        echo "No Docker images to remove."
    fi

    docker system prune -a --volumes || status=$?
    return $status
}

ssh() {
    TERM=xterm-256color command ssh "$@"
}

pg() {
    local use_newest=0
    local query
    local output
    local ps_output
    local status
    local pid_csv=""
    local pid_line
    local line
    local pid
    local user
    local cpu
    local mem
    local elapsed
    local cmd
    local cmd_highlighted
    local match_count=0
    local mode_text="all matches"
    local user_color
    local cpu_color
    local mem_color
    local elapsed_color
    local current_user="${USER:-$(id -un 2>/dev/null || true)}"

    # ANSI colors only when writing to a terminal.
    local c_reset="" c_bold="" c_magenta="" c_cyan="" c_green="" c_yellow="" c_red="" c_blue="" c_hilite=""
    if [ -t 1 ]; then
        c_reset=$'\033[0m'
        c_bold=$'\033[1m'
        c_magenta=$'\033[35m'
        c_cyan=$'\033[36m'
        c_green=$'\033[32m'
        c_yellow=$'\033[33m'
        c_red=$'\033[31m'
        c_blue=$'\033[34m'
        c_hilite=$'\033[1;95m'
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -n|--newest)
                use_newest=1
                mode_text="newest only"
                shift
                ;;
            -h|--help)
                printf "Usage: pg [-n|--newest] <pattern>\n"
                printf "       pg --help\n"
                return 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                printf "%s[pg]%s Unknown option: %s\n" "$c_red" "$c_reset" "$1" >&2
                printf "Usage: pg [-n|--newest] <pattern>\n" >&2
                return 2
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$#" -eq 0 ]; then
        printf "Usage: pg [-n|--newest] <pattern>\n" >&2
        return 2
    fi

    query="$*"

    local flags=(-i -f)
    if [ "$use_newest" -eq 1 ]; then
        flags+=(-n)
    fi
    output=$(pgrep "${flags[@]}" -- "$query")
    status=$?

    if [ "$status" -eq 0 ]; then
        match_count=$(printf "%s\n" "$output" | awk 'NF { count += 1 } END { print count + 0 }')
        printf "%s%s[pg]%s query: %s%s%s (%s)\n" "$c_bold" "$c_magenta" "$c_reset" "$c_bold" "$query" "$c_reset" "$mode_text"
        printf "%s%s[pg]%s matches: %s%d%s\n\n" "$c_bold" "$c_magenta" "$c_reset" "$c_green" "$match_count" "$c_reset"

        while IFS= read -r pid_line; do
            [ -n "$pid_line" ] || continue
            if [ -z "$pid_csv" ]; then
                pid_csv="$pid_line"
            else
                pid_csv="$pid_csv,$pid_line"
            fi
        done <<< "$output"

        printf "%s%-7s%s %s%-12s%s %s%6s%s %s%6s%s %s%-10s%s %s%s%s\n" \
            "${c_bold}${c_cyan}" "PID" "$c_reset" \
            "${c_bold}${c_green}" "USER" "$c_reset" \
            "${c_bold}${c_magenta}" "CPU%" "$c_reset" \
            "${c_bold}${c_yellow}" "MEM%" "$c_reset" \
            "${c_bold}${c_red}" "ELAPSED" "$c_reset" \
            "${c_bold}${c_hilite}" "COMMAND" "$c_reset"
        printf "%s\n" "----------------------------------------------------------------------------------------------"

        ps_output=$(ps -p "$pid_csv" -o pid=,user=,pcpu=,pmem=,etime=,command= 2>/dev/null || true)
        if [ -z "$ps_output" ]; then
            # Fallback: if ps details are unavailable, at least show matching PIDs.
            while IFS= read -r pid_line; do
                [ -n "$pid_line" ] || continue
                printf "%s%-7s%s\n" "$c_cyan" "$pid_line" "$c_reset"
            done <<< "$output"
            return "$status"
        fi

        while IFS= read -r line; do
            [ -n "$line" ] || continue
            read -r pid user cpu mem elapsed cmd <<< "$line"

            if [ -n "$current_user" ] && [ "$user" = "$current_user" ]; then
                user_color="$c_green"
            else
                user_color="$c_yellow"
            fi

            cpu_color="$c_magenta"
            mem_color="$c_yellow"
            elapsed_color="$c_red"

            if [ -n "$c_hilite" ]; then
                cmd_highlighted=$(awk -v text="$cmd" -v needle="$query" -v start="$c_hilite" -v stop="$c_reset" '
                BEGIN {
                    if (needle == "" || start == "") {
                        printf "%s", text
                        exit
                    }
                    lower_text = tolower(text)
                    lower_needle = tolower(needle)
                    needle_len = length(needle)
                    pos = 1
                    while (pos <= length(text)) {
                        idx = index(substr(lower_text, pos), lower_needle)
                        if (idx == 0) {
                            printf "%s", substr(text, pos)
                            break
                        }
                        abs = pos + idx - 1
                        printf "%s", substr(text, pos, abs - pos)
                        printf "%s%s%s", start, substr(text, abs, needle_len), stop
                        pos = abs + needle_len
                    }
                }')
            else
                cmd_highlighted="$cmd"
            fi

            printf "%s%-7s%s %s%-12s%s %s%6s%s %s%6s%s %s%-10s%s %s\n" \
                "$c_cyan" "$pid" "$c_reset" \
                "$user_color" "$user" "$c_reset" \
                "$cpu_color" "$cpu" "$c_reset" \
                "$mem_color" "$mem" "$c_reset" \
                "$elapsed_color" "$elapsed" "$c_reset" \
                "$cmd_highlighted"
        done <<< "$ps_output"
    elif [ "$status" -eq 1 ]; then
        printf "%s[pg]%s no matches for: %s\n" "$c_yellow" "$c_reset" "$query"
    else
        printf "%s[pg]%s pgrep failed for: %s\n" "$c_red" "$c_reset" "$query" >&2
    fi

    return "$status"
}

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
