h() {
    if [ "$#" -eq 0 ]; then
        history
        return $?
    fi

    history | rg -i -- "$*"
}
