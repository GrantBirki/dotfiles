# https://github.com/GrantBirki/dotfiles

# ~/.bashrc: executed by bash(1) for interactive non-login shells.

case $- in
  *i*) ;;
    *) return;;
esac

resolve_dotfiles_root() {
  local source_path="${BASH_SOURCE[0]}"
  local source_dir

  while [ -L "$source_path" ]; do
    source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
    source_path="$(readlink "$source_path")"
    case "$source_path" in
      /*) ;;
      *) source_path="$source_dir/$source_path" ;;
    esac
  done

  source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
  cd "$source_dir/.." && pwd
}

DOTFILES_ROOT="${DOTFILES_ROOT:-$(resolve_dotfiles_root)}"
export DOTFILES_ROOT

for module in \
  path \
  history \
  homebrew \
  completion \
  prompt \
  input \
  ssh-gpg \
  editor \
  languages \
  socket-firewall
do
  module_path="$DOTFILES_ROOT/shell/$module.bash"
  [ -r "$module_path" ] && . "$module_path"
done
unset module module_path

if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi
