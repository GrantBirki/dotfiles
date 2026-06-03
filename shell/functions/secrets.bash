set_secret() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: set_secret VAR_NAME" >&2
        return 2
    fi

    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "set_secret requires a valid shell variable name." >&2
        return 2
    fi

    set -- "$1" "_dotfiles_set_secret_value_$$"
    while [ "$1" = "$2" ]; do
        set -- "$1" "${2}_x"
    done

    local "$2"
    if ! read -rs -p "${1}=" "$2"; then
        echo >&2
        unset "$2"
        return 1
    fi
    echo

    printf -v "$1" '%s' "${!2}"
    unset "$2"
    export "$1"
}
