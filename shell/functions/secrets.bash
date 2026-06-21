set_secret() {
    case "${1:-}" in
        --confirm)
            set -- 2 "${@:2}"
            ;;
        --confirm=2)
            set -- 2 "${@:2}"
            ;;
        --confirm=3)
            set -- 3 "${@:2}"
            ;;
        --confirm=*)
            echo "set_secret --confirm only accepts 2 or 3." >&2
            return 2
            ;;
        --)
            set -- 1 "${@:2}"
            ;;
        --*)
            echo "Unknown set_secret option: $1" >&2
            return 2
            ;;
        *)
            set -- 1 "$@"
            ;;
    esac

    if [ "$#" -ne 2 ]; then
        echo "Usage: set_secret [--confirm[=2|3]] VAR_NAME" >&2
        return 2
    fi

    if [[ ! "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "set_secret requires a valid shell variable name." >&2
        return 2
    fi

    case $- in
        *x*)
            set +x
            set -- "$1" "$2" 1
            ;;
        *)
            set -- "$1" "$2" 0
            ;;
    esac

    set -- "$1" "$2" "$3" "_dotfiles_set_secret_value_$$" "_dotfiles_set_secret_confirm_$$" 1
    while [ "$2" = "$4" ] || [ "$2" = "$5" ] || [ "$4" = "$5" ]; do
        set -- "$1" "$2" "$3" "${4}_x" "${5}_x" "$6"
    done

    local "$4" "$5"
    if ! read -rs -p "${2}=" "$4"; then
        echo >&2
        unset "$4" "$5"
        if [ "$3" -eq 1 ]; then
            set -x
        fi
        return 1
    fi
    echo

    while [ "$6" -lt "$1" ]; do
        set -- "$1" "$2" "$3" "$4" "$5" "$(( $6 + 1 ))" "${2} (confirm)="

        if [ "$6" -eq 3 ]; then
            set -- "$1" "$2" "$3" "$4" "$5" "$6" "${2} (confirm again)="
        fi

        if ! read -rs -p "$7" "$5"; then
            echo >&2
            unset "$4" "$5"
            if [ "$3" -eq 1 ]; then
                set -x
            fi
            return 1
        fi
        echo

        if [ "${!4}" != "${!5}" ]; then
            echo "set_secret confirmation did not match." >&2
            unset "$4" "$5"
            if [ "$3" -eq 1 ]; then
                set -x
            fi
            return 1
        fi
        unset "$5"
    done

    printf -v "$2" '%s' "${!4}"
    unset "$4" "$5"
    export "$2"
    if [ "$3" -eq 1 ]; then
        set -x
    fi
}
