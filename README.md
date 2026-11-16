# qBittorrent Zeropoint module

This module runs qBittorrent in a Docker container managed by Zeropoint using Terraform and the Docker provider.

## Requirements

- Terraform >= 1.0
- Docker provider ~> 3.0
- Docker with support for the requested target architecture

## Usage

### Via Zeropoint API

```bash
curl -X POST http://<zeropoint-node-name>:2370/modules/install \
  -H "Content-Type: application/json" \
  -d '{
    "source": "https://github.com/zeropoint-os/qbittorrent.git",
    "module_id": "qbittorrent",
    "arch": "arm64"
  }'
```

### Manual testing

Use the VS Code tasks (Shift+Alt+T):

1. **Full Test: Setup and Apply**
2. **Test: Run qBittorrent Test Script**
3. **Full Test: Cleanup**

The test tasks run with Docker-in-Docker.

## Inputs

| Name | Type | Description | Default |
|------|------|-------------|---------|
| `zp_module_id` | string | Unique identifier for this module instance | `"qbittorrent"` |
| `zp_network_name` | string | Pre-created Docker network name (injected by Zeropoint) | (required) |
| `zp_arch` | string | Target architecture, such as `amd64` or `arm64` | `"amd64"` |
| `zp_gpu_vendor` | string | Unused GPU vendor value retained for Zeropoint compatibility | `""` |
| `zp_module_dir` | string | Module working directory supplied by Zeropoint | (required) |
| `zp_storage_dir` | string | Isolated data root for persistent module data | (required) |

## Storage

The module stores qBittorrent configuration in `${zp_storage_dir}/config` and downloaded files in `${zp_storage_dir}/downloads`. Both bind mounts remain under the module's isolated storage root.

## Network and service discovery

The container joins the pre-created network supplied through `zp_network_name`, with no host ports bound directly by this module. Other containers can reach qBittorrent at `${zp_module_id}-main`.

| Service | Port | Transport | Description |
|---------|------|-----------|-------------|
| Web UI | 8080 | TCP | HTTP web interface |
| BitTorrent | 6881 | TCP | Peer connections |
| BitTorrent | 6881 | UDP | Peer connections and DHT |

The Web UI URL from another container is `http://qbittorrent-main:8080/` when using the default module ID. The image may generate a temporary Web UI password; check container logs for the current login instructions and change the password after signing in.
