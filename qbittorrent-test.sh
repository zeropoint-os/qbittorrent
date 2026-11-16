#!/bin/bash

set -euo pipefail

container_name="${1:-qbittorrent-main}"
if ! container_ip=$(docker inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'); then
    echo "Error: container $container_name not found"
    exit 1
fi

if [ -z "$container_ip" ]; then
    echo "Error: container $container_name has no Docker network IP"
    exit 1
fi

echo "Checking qBittorrent web interface at $container_ip:8080..."
curl --fail --silent --show-error --max-time 10 --output /dev/null "http://$container_ip:8080/"
echo
echo "qBittorrent web interface is responding."
