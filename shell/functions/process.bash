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
    if output=$(pgrep "${flags[@]}" -- "$query"); then
        status=0
    else
        status=$?
    fi

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
