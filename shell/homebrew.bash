# shellcheck shell=bash

export BASH_SILENCE_DEPRECATION_WARNING=1

if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -d "$HOMEBREW_PREFIX/opt/rustup/bin" ]; then
  path_prepend "$HOMEBREW_PREFIX/opt/rustup/bin"
fi
