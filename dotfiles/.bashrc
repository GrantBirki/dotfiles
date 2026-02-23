# https://github.com/GrantBirki/dotfiles

# ~/.bashrc: executed by bash(1) for non-login shells (run on every terminal session type commands)

# If not running interactively, don't do anything
case $- in
  *i*) ;;
    *) return;;
esac

path_prepend() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
  esac
}

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTCONTROL=ignoredups:erasedups  # no duplicate entries
HISTSIZE=100000                   # big big history
HISTFILESIZE=100000               # big big history
shopt -s histappend               # append to history, don't overwrite it

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Linux-only color aliases from default distro templates.
if [[ "$OSTYPE" != "darwin"* ]] && [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Add an "alert" alias for long running commands when notify-send exists.
# Use like so: sleep 10; alert
if command -v notify-send >/dev/null 2>&1; then
  alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi


# Homebrew bash completions (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  bash_major=${BASH_VERSINFO[0]:-0}
  if (( bash_major >= 4 )); then
    if [[ -r /opt/homebrew/etc/bash_completion ]]; then
      . /opt/homebrew/etc/bash_completion
    elif [[ -d /opt/homebrew/etc/bash_completion.d ]]; then
      for completion in /opt/homebrew/etc/bash_completion.d/*; do
        [[ -r "$completion" ]] && . "$completion"
      done
    fi
  elif [[ -d /opt/homebrew/etc/bash_completion.d ]]; then
    for completion in /opt/homebrew/etc/bash_completion.d/*; do
      [[ -r "$completion" ]] && . "$completion"
    done
  fi
fi

# Git branch coloring and PS1
parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}
export PS1="\u@\h \[\e[32m\]\w \[\e[91m\]\$(parse_git_branch)\[\e[00m\]\n$ "

# Enable tab complete
bind TAB:menu-complete

# Get OS info
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  os="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  os="mac"
elif [[ "$OSTYPE" == "cygwin" ]]; then
  os="cygwin"
elif [[ "$OSTYPE" == "msys" ]]; then
  os="msys"
elif [[ "$OSTYPE" == "win32" ]]; then
  os="win"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
  os="freebsd"
else
  os="unknown"
fi

# SSH Keys
if [[ "$CODESPACES" != "true" ]]; then
  SSH_ENV="$HOME/.ssh/agent-environment"
  function start_agent {
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
  }
  if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    if [ -z "${SSH_AGENT_PID:-}" ] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
      start_agent
    fi
  else
    start_agent
  fi
fi

# GPG
export GPG_TTY=$(tty)

# PATH
path_prepend "$HOME/bin"

# Default editor
if [[ -z "$EDITOR" ]]; then
  # if code is installed, use it as the default editor
  if command -v code &> /dev/null; then
    export EDITOR="code --wait"
  else
    export EDITOR="nano"
  fi
fi

# linux config
if [[ $os == 'linux' && "$CODESPACES" != "true" ]]; then
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
fi

# macos config
if [[ $os == 'mac' && "$CODESPACES" != "true" ]]; then
  export BASH_SILENCE_DEPRECATION_WARNING=1
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -d "$HOMEBREW_PREFIX/opt/rustup/bin" ]; then
    # Prefer Homebrew's keg-only rustup bin.
    path_prepend "$HOMEBREW_PREFIX/opt/rustup/bin"
  fi

  # Bind Ctrl+Left Arrow to move backward by word
  bind '"\e[1;5D": backward-word'

  # Bind Ctrl+Right Arrow to move forward by word
  bind '"\e[1;5C": forward-word'
fi

if [[ "$CODESPACES" != "true" ]]; then
  # rbenv
  path_prepend "$HOME/.rbenv/shims"
  path_prepend "$HOME/.rbenv/bin"

  # tfenv
  path_prepend "$HOME/.tfenv/bin"

  # goenv - needs to go towards the bottom as it modifies the PATH
  # https://github.com/go-nv/goenv
  # for usage in visual studio code: https://github.com/go-nv/goenv/issues/293#issuecomment-2248260404
  # running `$ goenv rehash` often and fully rebooting vscode is a must
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

  mkdir -p "$CARGO_HOME"

  # Source rustup's env file when present.
  if [ -f "$CARGO_HOME/env" ]; then
    . "$CARGO_HOME/env"
  fi

  case ":$PATH:" in
    *":$CARGO_HOME/bin:"*) ;;
    *) path_prepend "$CARGO_HOME/bin" ;;
  esac

  # crystal
  if [[ $os == 'mac' ]]; then
    export CRYSTAL_OPTS="--link-flags=-Wl"
  else
    # I don't use crenv on macos, so only run this on linux
    # crenv on macos lacks support, especially for arm64
    path_prepend "$HOME/.crenv/bin"
    if command -v crenv >/dev/null 2>&1; then
      eval "$(crenv init -)"
    fi
    export CRENV_ROOT="$HOME/.crenv"
  fi
  # https://github.com/GrantBirki/crystal-base-template/pull/11/commits/4481750a1dae141832f76ad0d79137cdb385852e
  if command -v crystal >/dev/null 2>&1; then
    export CRYSTAL_PATH="vendor/shards/install:$(crystal env CRYSTAL_PATH)"
  fi
fi

# if the ~/.local/bin/ directory doesn't exist, create it
if [ ! -d "$HOME/.local/bin" ]; then
  echo "first time setup: creating ~/.local/bin directory"
  mkdir -p "$HOME/.local/bin"
fi

# add ~/.local/bin/ to the PATH as it is where my custom binaries are stored
path_prepend "$HOME/.local/bin"
