# shellcheck shell=bash

bash_major=${BASH_VERSINFO[0]:-0}
completion_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"

if (( bash_major >= 4 )); then
  if [[ -r "$completion_prefix/etc/bash_completion" ]]; then
    . "$completion_prefix/etc/bash_completion"
  elif [[ -d "$completion_prefix/etc/bash_completion.d" ]]; then
    for completion in "$completion_prefix"/etc/bash_completion.d/*; do
      [[ -r "$completion" ]] && . "$completion"
    done
  fi
elif [[ -d "$completion_prefix/etc/bash_completion.d" ]]; then
  for completion in "$completion_prefix"/etc/bash_completion.d/*; do
    [[ -r "$completion" ]] && . "$completion"
  done
fi

unset bash_major completion completion_prefix
