set_secret() {
    set -- 1 1 "$@"
    while [ "$#" -gt 2 ]; do
        case "$3" in
            --confirm)
                set -- 2 "$2" "${@:4}"
                ;;
            --confirm=2)
                set -- 2 "$2" "${@:4}"
                ;;
            --confirm=3)
                set -- 3 "$2" "${@:4}"
                ;;
            --confirm=*)
                echo "set_secret --confirm only accepts 2 or 3." >&2
                return 2
                ;;
            --no-export)
                set -- "$1" 0 "${@:4}"
                ;;
            --)
                set -- "$1" "$2" "${@:4}"
                break
                ;;
            --*)
                echo "Unknown set_secret option: $3" >&2
                return 2
                ;;
            *)
                break
                ;;
        esac
    done

    if [ "$#" -ne 3 ]; then
        echo "Usage: set_secret [--no-export] [--confirm[=2|3]] VAR_NAME" >&2
        return 2
    fi

    if [[ ! "$3" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "set_secret requires a valid shell variable name." >&2
        return 2
    fi

    case $- in
        *x*)
            set +x
            set -- "$1" "$2" "$3" 1
            ;;
        *)
            set -- "$1" "$2" "$3" 0
            ;;
    esac

    set -- "$1" "$2" "$3" "$4" "_dotfiles_set_secret_value_$$" "_dotfiles_set_secret_confirm_$$" 1
    while [ "$3" = "$5" ] || [ "$3" = "$6" ] || [ "$5" = "$6" ]; do
        set -- "$1" "$2" "$3" "$4" "${5}_x" "${6}_x" "$7"
    done

    local "$5" "$6"
    if ! read -rs -p "${3}=" "$5"; then
        echo >&2
        unset "$5" "$6"
        if [ "$4" -eq 1 ]; then
            set -x
        fi
        return 1
    fi
    echo

    while [ "$7" -lt "$1" ]; do
        set -- "$1" "$2" "$3" "$4" "$5" "$6" "$(( $7 + 1 ))" "${3} (confirm)="

        if [ "$7" -eq 3 ]; then
            set -- "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${3} (confirm again)="
        fi

        if ! read -rs -p "$8" "$6"; then
            echo >&2
            unset "$5" "$6"
            if [ "$4" -eq 1 ]; then
                set -x
            fi
            return 1
        fi
        echo

        if [ "${!5}" != "${!6}" ]; then
            echo "set_secret confirmation did not match." >&2
            unset "$5" "$6"
            if [ "$4" -eq 1 ]; then
                set -x
            fi
            return 1
        fi
        unset "$6"
    done

    printf -v "$3" '%s' "${!5}"
    unset "$5" "$6"
    if [ "$2" -eq 1 ]; then
        export "$3"
    else
        export -n "$3"
    fi
    if [ "$4" -eq 1 ]; then
        set -x
    fi
}
