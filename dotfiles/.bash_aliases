# https://github.com/GrantBirki/dotfiles
#
# Alias/function documentation contract:
# - Any user-facing `alias name='...'` added here must be documented in
#   `dotfiles/.aliases.yml` with `name`, `args`, and `description`.
# - Any user-facing bash function that acts like a command must also be
#   documented in `dotfiles/.aliases.yml` and listed in
#   `ALIASES_TRACKED_FUNCTIONS` below.
# - Internal helper functions should be prefixed with `_` or intentionally
#   omitted from `ALIASES_TRACKED_FUNCTIONS`.
# - After editing aliases or shell/functions, run
#   `source dotfiles/.bash_aliases && aliases`.

if [ -z "${DOTFILES_ROOT:-}" ]; then
    _dotfiles_alias_source="${BASH_SOURCE[0]}"
    _dotfiles_alias_dir="$(cd "$(dirname "$_dotfiles_alias_source")" && pwd)"
    DOTFILES_ROOT="$(cd "$_dotfiles_alias_dir/.." && pwd)"
    export DOTFILES_ROOT
    unset _dotfiles_alias_source _dotfiles_alias_dir
fi

alias ls='eza --group-directories-first --color=auto'
alias ll='ls -lahg --time-style="+%Y-%m-%d %H:%M:%S" --total-size --octal-permissions --no-permissions'
alias la='ls -A'
alias l='ls'
alias lss='eza -lag --time-style=long-iso'
alias c='clear'
alias celar='clear'
alias cdc='cd ~/code'
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
alias ss='set_secret'
alias gp='git pull'
alias npm='_dotfiles_sfw_exec npm'
alias yarn='_dotfiles_sfw_exec yarn'
alias pnpm='_dotfiles_sfw_exec pnpm'
alias pip='_dotfiles_sfw_exec pip'
alias uv='_dotfiles_sfw_exec uv'
alias cargo='_dotfiles_sfw_exec cargo'

# User-facing bash functions that should always exist in .aliases.yml.
ALIASES_TRACKED_FUNCTIONS=(h gbr gcm dockernuke pg ssh ssh-with-key set_secret aliases_help aliases sfw_status)

for _dotfiles_function_module in \
    history \
    secrets \
    git \
    docker \
    process \
    ssh \
    socket-firewall \
    alias-help
do
    source "$DOTFILES_ROOT/shell/functions/${_dotfiles_function_module}.bash"
done
unset _dotfiles_function_module

alias aliases='aliases_help'
