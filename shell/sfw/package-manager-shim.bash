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
    if ! command -v sfw >/dev/null 2>&1; then
        printf "dotfiles-sfw-shim: real sfw not found after removing shim dir\n" >&2
        printf "dotfiles-sfw-shim: install with: DOTFILES_SFW_DISABLE=1 npm i -g sfw && nodenv rehash\n" >&2
        exit 127
    fi

    export DOTFILES_SFW_ACTIVE=1
    exec sfw "$@"
fi

if [ "${DOTFILES_SFW_DISABLE:-0}" = "1" ] || [ "${DOTFILES_SFW_ACTIVE:-0}" = "1" ]; then
    exec "$cmd" "$@"
fi

if ! command -v sfw >/dev/null 2>&1; then
    if [ "${DOTFILES_SFW_REQUIRE:-1}" = "1" ]; then
        printf "dotfiles-sfw-shim: refusing to run %s unprotected because sfw is unavailable\n" "$cmd" >&2
        printf "dotfiles-sfw-shim: install with: DOTFILES_SFW_DISABLE=1 npm i -g sfw && nodenv rehash\n" >&2
        exit 127
    fi

    printf "dotfiles-sfw-shim: warning: sfw unavailable; running %s unprotected\n" "$cmd" >&2
    exec "$cmd" "$@"
fi

if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "dotfiles-sfw-shim: real package manager not found: %s\n" "$cmd" >&2
    exit 127
fi

export DOTFILES_SFW_ACTIVE=1
exec sfw "$cmd" "$@"
