# Socket Firewall Free helpers for supported package managers.

_dotfiles_sfw_supported_command() {
    case "$1" in
        npm|yarn|pnpm|pip|uv|cargo) return 0 ;;
        *) return 1 ;;
    esac
}

_dotfiles_sfw_path_without_shims() {
    local shim_dir="${DOTFILES_SFW_SHIM_DIR:-$HOME/.local/share/dotfiles/sfw-shims}"
    local old_ifs="$IFS"
    local part
    local out=""

    IFS=:
    for part in $PATH; do
        [ -n "$part" ] || continue
        [ "$part" = "$shim_dir" ] && continue
        out="${out:+$out:}$part"
    done
    IFS="$old_ifs"

    printf "%s\n" "$out"
}

_dotfiles_sfw_exec() {
    local cmd="$1"
    shift || true

    if ! _dotfiles_sfw_supported_command "$cmd"; then
        printf "dotfiles: unsupported Socket Firewall command: %s\n" "$cmd" >&2
        return 2
    fi

    local clean_path
    clean_path="$(_dotfiles_sfw_path_without_shims)"

    if [ "${DOTFILES_SFW_DISABLE:-0}" = "1" ]; then
        PATH="$clean_path" command "$cmd" "$@"
        return $?
    fi

    if ! PATH="$clean_path" command -v sfw >/dev/null 2>&1; then
        if [ "${DOTFILES_SFW_REQUIRE:-1}" = "1" ]; then
            printf "dotfiles: refusing to run %s unprotected because sfw is unavailable\n" "$cmd" >&2
            printf "dotfiles: install with: DOTFILES_SFW_DISABLE=1 npm i -g sfw && nodenv rehash\n" >&2
            return 127
        fi

        printf "dotfiles: warning: sfw unavailable; running %s unprotected\n" "$cmd" >&2
        PATH="$clean_path" command "$cmd" "$@"
        return $?
    fi

    if ! PATH="$clean_path" command -v "$cmd" >/dev/null 2>&1; then
        printf "dotfiles: real package manager not found: %s\n" "$cmd" >&2
        return 127
    fi

    PATH="$clean_path" command sfw "$cmd" "$@"
}

sfw_status() {
    local shim_dir="${DOTFILES_SFW_SHIM_DIR:-$HOME/.local/share/dotfiles/sfw-shims}"
    local clean_path
    local cmd

    clean_path="$(_dotfiles_sfw_path_without_shims)"

    printf "Socket Firewall status\n"
    printf "  shim dir:     %s\n" "$shim_dir"
    printf "  require mode: %s\n" "${DOTFILES_SFW_REQUIRE:-1}"
    printf "  disabled:     %s\n" "${DOTFILES_SFW_DISABLE:-0}"
    printf "\n"

    for cmd in sfw npm yarn pnpm pip uv cargo; do
        printf "%-6s protected:   %s\n" "$cmd" "$(command -v "$cmd" 2>/dev/null || printf "<missing>")"
        printf "%-6s unprotected: %s\n" "$cmd" "$(PATH="$clean_path" command -v "$cmd" 2>/dev/null || printf "<missing>")"
    done
}
