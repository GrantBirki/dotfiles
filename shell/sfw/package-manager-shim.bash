#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

cmd="${0##*/}"

case "$cmd" in
    sfw|npm|yarn|pnpm|pip|uv|cargo) ;;
    *)
        printf "dotfiles-sfw-shim: unsupported shim name: %s\n" "$cmd" >&2
        exit 2
        ;;
esac

shim_dir="${DOTFILES_SFW_SHIM_DIR:-$HOME/.local/share/dotfiles/sfw-shims}"
sfw_bin="${DOTFILES_SFW_BIN:-$HOME/.local/bin/sfw}"

path_without_shims() {
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

clean_path="$(path_without_shims)"
export PATH="$clean_path"

if [ "$cmd" = "sfw" ]; then
    if [ ! -x "$sfw_bin" ]; then
        printf "dotfiles-sfw-shim: DOTFILES_SFW_BIN not found or not executable: %s\n" "$sfw_bin" >&2
        printf "dotfiles-sfw-shim: install with: script/socket-firewall install\n" >&2
        exit 127
    fi

    exec "$sfw_bin" "$@"
fi

if [ "${DOTFILES_SFW_DISABLE:-0}" = "1" ]; then
    exec "$cmd" "$@"
fi

if [ ! -x "$sfw_bin" ]; then
    if [ "${DOTFILES_SFW_REQUIRE:-1}" = "1" ]; then
        printf "dotfiles-sfw-shim: refusing to run %s unprotected because DOTFILES_SFW_BIN is unavailable\n" "$cmd" >&2
        printf "dotfiles-sfw-shim: install with: script/socket-firewall install\n" >&2
        exit 127
    fi

    printf "dotfiles-sfw-shim: warning: DOTFILES_SFW_BIN unavailable; running %s unprotected\n" "$cmd" >&2
    exec "$cmd" "$@"
fi

if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "dotfiles-sfw-shim: real package manager not found: %s\n" "$cmd" >&2
    exit 127
fi

exec "$sfw_bin" "$cmd" "$@"
