# shellcheck shell=bash

# rbenv
path_prepend "$HOME/.rbenv/shims"
path_prepend "$HOME/.rbenv/bin"

# tfenv
path_prepend "$HOME/.tfenv/bin"

# goenv
export GOENV_ROOT="$HOME/.goenv"
path_prepend "$GOENV_ROOT/bin"
if command -v goenv >/dev/null 2>&1; then
  eval "$(goenv init -)"
fi
export GOPROXY="https://proxy.golang.org/,direct"
export GONOSUMDB="github.com/github/*"

# nodenv
if command -v nodenv >/dev/null 2>&1; then
  eval "$(nodenv init -)"
fi

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
path_prepend "$PYENV_ROOT/bin"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi

# cargo / rust
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
if [ -f "$CARGO_HOME/env" ]; then
  . "$CARGO_HOME/env"
fi
path_prepend "$CARGO_HOME/bin"
