# shellcheck shell=bash

if [[ -z "${EDITOR:-}" ]]; then
  if command -v code >/dev/null 2>&1; then
    export EDITOR="code --wait"
  else
    export EDITOR="nano"
  fi
fi
