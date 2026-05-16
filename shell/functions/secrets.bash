set_secret() {
    local var_name="${1:-}"
    local secret_value=""

    if [ "$#" -ne 1 ]; then
        echo "Usage: set_secret VAR_NAME" >&2
        return 2
    fi

    if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "set_secret requires a valid shell variable name." >&2
        return 2
    fi

    if ! read -rs -p "${var_name}=" secret_value; then
        echo >&2
        return 1
    fi
    echo

    printf -v "$var_name" '%s' "$secret_value"
    export "$var_name"
    unset secret_value
}
