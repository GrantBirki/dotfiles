# https://github.com/GrantBirki/dotfiles

# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login exists
# On my mac devices, I just delete the .bash_profile and .bash_login files and use .bashrc and .profile instead

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

profile_path_prepend() {
    if [ -d "$1" ]; then
        case ":$PATH:" in
            *":$1:"*) ;;
            *) PATH="$1:$PATH" ;;
        esac
    fi
}

# set PATH so it includes user's private bin if it exists
profile_path_prepend "$HOME/bin"

# set PATH so it includes user's private bin if it exists
profile_path_prepend "$HOME/.local/bin"

export PATH
