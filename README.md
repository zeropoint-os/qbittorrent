# qBittorrent Zeropoint module

This module runs qBittorrent in a Docker container managed by Zeropoint using Terraform and the Docker provider.

## Requirements

- Terraform >= 1.0
- Docker provider ~> 3.0
- Docker with support for the requested target architecture
- An unused host port for qBittorrent TCP and UDP peer traffic

## Installation through the Zeropoint API

Pin the module source to a reviewed 40-character commit SHA. User-configurable Terraform inputs belong in `overrides`; `media_path` can initially be a host path and later resolve from a canonical Zeropoint storage Var.

```bash
curl -X POST http://<zeropoint-node-name>:2370/api/modules \
  -H "Content-Type: application/json" \
  -d '{
    "source": "https://github.com/zeropoint-os/qbittorrent.git@<40-character-commit-sha>",
    "overrides": {
      "media_path": "/srv/media/downloads",
      "puid": 1000,
      "pgid": 1000,
      "timezone": "Etc/UTC",
      "torrenting_port": 6881
    },
    "resolve": true
  }'
```

## Inputs

| Name | Type | Description | Default |
|------|------|-------------|---------|
| `zp_module_id` | string | Unique identifier for this module instance | `"qbittorrent"` |
| `zp_network_name` | string | Pre-created Docker network name (injected by Zeropoint) | (required) |
| `zp_arch` | string | Target architecture, such as `amd64` or `arm64` | `"amd64"` |
| `zp_gpu_vendor` | string | Unused GPU vendor value retained for Zeropoint compatibility | `""` |
| `zp_module_dir` | string | Module working directory supplied by Zeropoint | (required) |
| `zp_storage_dir` | string | Isolated data root for persistent module data | (required) |
| `media_path` | string or null | Host path mounted read-write at `/media` | `null` (`${zp_storage_dir}/downloads`) |
| `puid` | number | LinuxServer container user ID | `1000` |
| `pgid` | number | LinuxServer container group ID | `1000` |
| `timezone` | string | Container timezone in TZ database format | `"Etc/UTC"` |
| `torrenting_port` | number | Stable inbound TCP and UDP peer port | `6881` |

## Storage

qBittorrent configuration is persisted at `${zp_storage_dir}/config`. Downloads are always persisted through the read-write `/media` mount: `media_path` when set, otherwise `${zp_storage_dir}/downloads`.

Set qBittorrent's default save path to a directory under `/media` in the Web UI. Supplying `media_path` as an override keeps download storage independent of module configuration storage and allows Zeropoint to link it to a canonical storage Var later.

## Network and service discovery

The container joins `zp_network_name`. The Web UI remains unbound on the host and is advertised through `main_ports` for Zeropoint HTTP exposure. Other containers can reach it at `http://${zp_module_id}-main:8080`.

BitTorrent peer traffic bypasses the HTTP exposure path. The module binds `torrenting_port` directly on the Docker host for both TCP and UDP, using the same port inside and outside the container so the advertised listening port stays reachable. Only one module or host service can claim a given TCP/UDP port pair; choose a different `torrenting_port` when there is a conflict and allow that port through the host firewall or upstream NAT as needed.

The LinuxServer image may generate a temporary Web UI password; inspect the container logs for the current login instructions and change the password after signing in.

## Manual validation

Use the VS Code tasks (Shift+Alt+T) inside the development container:

1. **Full Test: Setup and Apply**
2. **Test: Run qBittorrent Test Script**
3. **Full Test: Cleanup**

The smoke test checks the Web UI, `/config` and `/media` mounts, TCP/UDP host bindings, and persistence across forced container recreation.
