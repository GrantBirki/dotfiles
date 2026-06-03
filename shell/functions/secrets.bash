set_secret() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: set_secret VAR_NAME" >&2
        return 2
    fi

    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "set_secret requires a valid shell variable name." >&2
        return 2
    fi

    if ! read -rs -p "${1}=" "$1"; then
        echo >&2
        return 1
    fi
    echo

    export "$1"
}
