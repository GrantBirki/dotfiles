# shellcheck shell=bash

path_prepend() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
  esac
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"
