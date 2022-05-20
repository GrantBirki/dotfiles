alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias cdc='cd ~/code || cd /mnt/c/code'
alias gbr='git branch | grep -v -E "(master|main)" | xargs git branch -D'
alias gp='git pull'
alias gc='git checkout -b'
alias gpf='git fetch --all && echo -e "\033[1;34m[#]\033[0m Creating Back
up Branch: backup-$(git symbolic-ref --short -q HEAD)" && git branch back
up-$(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m F
orce Pull Current Branch from Remote Origin" && git reset --hard origin/$
(git symbolic-ref --short -q HEAD) && echo -e "\033[1;34m[#]\033[0m Curre
nt Branch is set to state of remote Origin and backup branch created."'
alias gcm='git checkout master'
alias lss='exa -lag --time-style=long-iso'
alias h='history | rg -i'
