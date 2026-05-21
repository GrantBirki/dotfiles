ssh() {
    TERM=xterm-256color command ssh "$@"
}

ssh-with-key() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: ssh-with-key <private-key-path> [ssh args...]" >&2
        return 2
    fi

    local key_path=$1
    shift

    if [ ! -r "$key_path" ]; then
        echo "SSH private key is not readable: $key_path" >&2
        return 1
    fi

    env -u SSH_AUTH_SOCK TERM=xterm-256color /usr/bin/ssh \
        -o "IdentitiesOnly=yes" \
        -o "IdentityFile=$key_path" \
        -o "AddKeysToAgent=no" \
        -o "UseKeychain=no" \
        "$@"
}
