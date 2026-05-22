# shellcheck shell=bash

# Socket Firewall Free integration.
#
# This module is loaded after shell/languages.bash so the protected shim
# directory outranks nodenv, pyenv, Cargo, and system package-manager paths.

export DOTFILES_SFW_SHIM_DIR="${DOTFILES_SFW_SHIM_DIR:-$HOME/.local/share/dotfiles/sfw-shims}"
export DOTFILES_SFW_REQUIRE="${DOTFILES_SFW_REQUIRE:-1}"

if [ "${DOTFILES_SFW_DISABLE:-0}" != "1" ]; then
  path_prepend "$DOTFILES_SFW_SHIM_DIR"
fi
