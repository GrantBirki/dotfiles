# https://github.com/GrantBirki/dotfiles

alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias cdc='cd ~/code || cd /mnt/c/code'
alias gbr='git branch | grep -v -E "(master|main)" | xargs git branch -D'
alias gp='git pull'
alias gc='git checkout -b'
alias gpf='git fetch --all && echo -e "\033[1;34m[#]\033[0m Creating Backup Branch: backup-$(git symbolic-ref --short -q HEAD)" && git branch backup-$(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m Force Pull Current Branch from Remote Origin" && git reset --hard origin/$(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m Current Branch is set to state of remote Origin and backup branch created."'
alias gcm='git checkout master 2> /dev/null || echo "master branch not found, trying main"; git checkout main'
alias lss='exa -lag --time-style=long-iso'
alias h='history | rg -i'
alias dockernuke='docker rm -vf $(docker ps -a -q) && docker rmi -f $(docker images -a -q) && docker system prune -a --volumes'
alias pbcopy='xsel --clipboard --input'
alias pbpaste='xsel --clipboard --output'
alias pss='ps -auxf | head -1 ; ps -auxf | grep -i'
alias ssh="TERM=xterm-256color $(which ssh)"

# if the platform is mac, use the mac aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

# since goenv is super finicky about rehashing, we have to rehash it every time we want to open vscode
# this is a workaround to ensure that the goenv rehash is run before opening vscode if it is installed
# perhaps in the future it might be wise to do this with other <lang>envs as well
# for the most part, other tools like pyenv, rbenv, etc. do not require this as they "JUST WORK"
# but goenv is a special case, so we have to do this (yayyyy)
alias code='(command -v goenv >/dev/null 2>&1 && goenv rehash); command code'
