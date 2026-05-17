dockernuke() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker command not found." >&2
        return 127
    fi

    local status=0
    local container_ids
    local image_ids

    container_ids=$(docker ps -a -q)
    if [ -n "$container_ids" ]; then
        docker rm -vf $container_ids || status=$?
    else
        echo "No Docker containers to remove."
    fi

    image_ids=$(docker images -a -q)
    if [ -n "$image_ids" ]; then
        docker rmi -f $image_ids || status=$?
    else
        echo "No Docker images to remove."
    fi

    docker system prune -a --volumes || status=$?
    return $status
}
