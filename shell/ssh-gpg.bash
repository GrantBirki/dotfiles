# shellcheck shell=bash

SECRETIVE_SSH_AUTH_SOCK="${SECRETIVE_SSH_AUTH_SOCK:-$HOME/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh}"

if [ -S "$SECRETIVE_SSH_AUTH_SOCK" ]; then
  export SSH_AUTH_SOCK="$SECRETIVE_SSH_AUTH_SOCK"
fi

if _dotfiles_tty="$(tty 2>/dev/null)"; then
  export GPG_TTY="$_dotfiles_tty"
fi
unset _dotfiles_tty
