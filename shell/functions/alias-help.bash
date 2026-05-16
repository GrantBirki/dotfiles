# Show documented aliases from YAML metadata in a readable format.
_find_aliases_yaml() {
    local candidate
    local candidates=(
        "$DOTFILES_ROOT/dotfiles/.aliases.yml"
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
