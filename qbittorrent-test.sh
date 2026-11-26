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
config_file="${storage_dir}/config/qBittorrent/qBittorrent.conf"
api_response_file="$(mktemp)"
original_save_path=""

trap 'rm -f "$api_response_file"' EXIT

mkdir -p "$storage_dir/config" "$media_path"

tf_vars=(
    -var="zp_network_name=${network_name}"
    -var="zp_module_dir=${module_dir}"
    -var="zp_storage_dir=${storage_dir}"
    -var="torrenting_port=${torrenting_port}"
)
if [ "$media_path" != "${storage_dir}/downloads" ]; then
    tf_vars+=(-var="media_path=${media_path}")
fi

apply_default_auth() {
    terraform apply "${tf_vars[@]}" -auto-approve >/dev/null
}

apply_auth_setting() {
    local enabled="$1"
    terraform apply "${tf_vars[@]}" -var="webui_auth_enabled=${enabled}" -auto-approve >/dev/null
}

container_ip() {
    docker inspect "$container_name" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
}

wait_for_webui() {
    local ip
    ip="$(container_ip)"
    for _ in $(seq 1 30); do
        if curl --fail --silent --max-time 2 --output /dev/null "http://${ip}:8080/"; then
            return 0
        fi
        sleep 1
    done
    echo "Error: qBittorrent Web UI did not become ready at ${ip}:8080" >&2
    return 1
}

api_status() {
    local ip
    ip="$(container_ip)"
    curl --silent --max-time 2 --output "$api_response_file" --write-out '%{http_code}' \
        "http://${ip}:8080/api/v2/app/version" || true
}

assert_webui_setting() {
    local expected="$1"
    docker exec "$container_name" awk -v expected="$expected" '
        /^\[WebUI\]$/ {
            in_webui = 1
            next
        }
        /^\[/ {
            in_webui = 0
        }
        in_webui && $0 == expected {
            found = 1
        }
        END {
            exit !found
        }
    ' /config/qBittorrent/qBittorrent.conf
}

assert_auth_enabled() {
    local status
    assert_webui_setting 'AuthSubnetWhitelistEnabled=false'
    status="$(api_status)"
    if [ "$status" = "200" ]; then
        echo "Error: qBittorrent API was accessible without authentication" >&2
        return 1
    fi
}

assert_auth_disabled() {
    local status
    assert_webui_setting 'AuthSubnetWhitelist=0.0.0.0/0, ::/0'
    assert_webui_setting 'AuthSubnetWhitelistEnabled=true'
    status="$(api_status)"
    if [ "$status" != "200" ]; then
        echo "Error: qBittorrent API still required authentication (HTTP ${status})" >&2
        return 1
    fi
    grep -Eq '^v?[0-9]+\.[0-9]+' "$api_response_file"
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

set_config_preference() {
    local key="$1"
    local value="$2"
    local temp_file
    temp_file="$(mktemp "$config_file.XXXXXX")"

    KEY="$key" VALUE="$value" awk '
        BEGIN {
            key = ENVIRON["KEY"]
            value = ENVIRON["VALUE"]
            in_preferences = 0
            found = 0
        }
        /^\[Preferences\]$/ {
            in_preferences = 1
            print
            next
        }
        /^\[/ {
            if (in_preferences && !found) {
                print key "=" value
                found = 1
            }
            in_preferences = 0
        }
        {
            if (in_preferences && index($0, key "=") == 1) {
                if (!found) {
                    print key "=" value
                    found = 1
                }
                next
            }
            print
        }
        END {
            if (in_preferences && !found) {
                print key "=" value
                found = 1
            }
            if (!found) {
                print ""
                print "[Preferences]"
                print key "=" value
            }
        }
    ' "$config_file" >"$temp_file"

    chown --reference="$config_file" "$temp_file"
    chmod --reference="$config_file" "$temp_file"
    mv "$temp_file" "$config_file"
}

assert_persistent_data() {
    grep -qx media "${media_path}/${media_marker}"
    grep -qx config "${storage_dir}/config/${config_marker}"
}

assert_preserved_preference() {
    grep -Fqx 'Downloads\SavePath=/media/auth-toggle-persistence/' "$config_file"
}

apply_default_auth
wait_for_webui
assert_contract
assert_auth_enabled

docker exec "$container_name" sh -c \
    "printf media > /media/${media_marker}; printf config > /config/${config_marker}"
docker stop "$container_name" >/dev/null
original_save_path="$(sed -n 's|^Downloads\\SavePath=||p' "$config_file" | head -n1)"
set_config_preference 'Downloads\SavePath' '/media/auth-toggle-persistence/'

apply_auth_setting false
wait_for_webui
assert_contract
assert_auth_disabled
assert_persistent_data
assert_preserved_preference

docker rm --force "$container_name" >/dev/null
apply_auth_setting false
wait_for_webui
assert_contract
assert_auth_disabled
assert_persistent_data
assert_preserved_preference

apply_auth_setting true
wait_for_webui
assert_contract
assert_auth_enabled
assert_persistent_data
assert_preserved_preference

docker stop "$container_name" >/dev/null
set_config_preference 'Downloads\SavePath' "$original_save_path"
rm -f "${media_path}/${media_marker}" "${storage_dir}/config/${config_marker}"
apply_auth_setting true
wait_for_webui
assert_contract
assert_auth_enabled

echo "qBittorrent Web UI auth default, disable, recreation, re-enable, persistent settings, mounts, and TCP/UDP bindings verified."
