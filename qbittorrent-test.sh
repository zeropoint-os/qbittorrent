#!/bin/bash

set -euo pipefail

container_name="${1:-qbittorrent-main}"
storage_dir="${2:-/workspaces/data}"
torrenting_port="${3:-6881}"
media_path="${4:-${storage_dir}/downloads}"
network_name="${5:-zpm-test-nw}"
module_dir="${6:-$PWD}"
media_marker=".qbittorrent-media-persistence-test"
config_marker=".qbittorrent-config-persistence-test"

tf_vars=(
    -var="zp_network_name=${network_name}"
    -var="zp_module_dir=${module_dir}"
    -var="zp_storage_dir=${storage_dir}"
    -var="torrenting_port=${torrenting_port}"
)
if [ "$media_path" != "${storage_dir}/downloads" ]; then
    tf_vars+=(-var="media_path=${media_path}")
fi

wait_for_webui() {
    local container_ip
    container_ip=$(docker inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
    for _ in $(seq 1 30); do
        if curl --fail --silent --show-error --max-time 2 --output /dev/null "http://${container_ip}:8080/"; then
            return 0
        fi
        sleep 1
    done
    echo "Error: qBittorrent Web UI did not become ready at ${container_ip}:8080" >&2
    return 1
}

assert_contract() {
    docker inspect "$container_name" | jq -e \
        --arg config_path "${storage_dir}/config" \
        --arg media_path "$media_path" \
        --arg tcp_port "${torrenting_port}/tcp" \
        --arg udp_port "${torrenting_port}/udp" \
        '.[0] as $container
         | any($container.Mounts[]; .Destination == "/config" and .Source == $config_path and .RW == true)
         and any($container.Mounts[]; .Destination == "/media" and .Source == $media_path and .RW == true)
         and ($container.HostConfig.PortBindings[$tcp_port] | length == 1)
         and ($container.HostConfig.PortBindings[$tcp_port][0].HostPort == ($tcp_port | split("/")[0]))
         and ($container.HostConfig.PortBindings[$udp_port] | length == 1)
         and ($container.HostConfig.PortBindings[$udp_port][0].HostPort == ($udp_port | split("/")[0]))
         and ($container.HostConfig.PortBindings["8080/tcp"] == null)' >/dev/null
}

wait_for_webui
assert_contract

docker exec "$container_name" sh -c "printf media > /media/${media_marker}; printf config > /config/${config_marker}"
docker rm --force "$container_name" >/dev/null
terraform apply "${tf_vars[@]}" -auto-approve >/dev/null

wait_for_webui
assert_contract
docker exec "$container_name" grep -qx media "/media/${media_marker}"
docker exec "$container_name" grep -qx config "/config/${config_marker}"

docker exec "$container_name" rm -f "/media/${media_marker}" "/config/${config_marker}"
echo "qBittorrent Web UI, persistent mounts, and TCP/UDP host bindings verified."
