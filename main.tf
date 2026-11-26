terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

variable "zp_module_id" {
  type        = string
  default     = "qbittorrent"
  description = "Unique identifier for this module instance (user-defined, freeform)"
}

variable "zp_network_name" {
  type        = string
  description = "Pre-created Docker network name for this module (managed by Zeropoint)"
}

variable "zp_arch" {
  type        = string
  default     = "amd64"
  description = "Target architecture - amd64, arm64, etc. (injected by Zeropoint)"
}

variable "zp_gpu_vendor" {
  type        = string
  default     = ""
  description = "GPU vendor - unused by this module (injected by Zeropoint)"
}

variable "zp_module_dir" {
  type        = string
  description = "Agent working directory for this module (injected by Zeropoint)"
}

variable "zp_storage_dir" {
  type        = string
  description = "Isolated data root for this module (injected by Zeropoint)"
}

variable "media_path" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional host path mounted read-write at /media; defaults to zp_storage_dir/downloads"
}

variable "puid" {
  type        = number
  default     = 1000
  description = "LinuxServer container user ID"
}

variable "pgid" {
  type        = number
  default     = 1000
  description = "LinuxServer container group ID"
}

variable "timezone" {
  type        = string
  default     = "Etc/UTC"
  description = "Container timezone in TZ database format"
}

variable "webui_auth_enabled" {
  type        = bool
  default     = true
  description = "Require qBittorrent Web UI authentication; disable only behind a trusted Zeropoint ingress/access layer"
}

variable "torrenting_port" {
  type        = number
  default     = 6881
  description = "Stable host and container port for inbound BitTorrent TCP and UDP traffic"

  validation {
    condition     = var.torrenting_port >= 1 && var.torrenting_port <= 65535
    error_message = "torrenting_port must be between 1 and 65535."
  }
}

locals {
  media_path = var.media_path != null ? var.media_path : "${var.zp_storage_dir}/downloads"

  webui_auth_init_script = <<-EOT
    #!/usr/bin/with-contenv bash
    set -euo pipefail

    config_file=/config/qBittorrent/qBittorrent.conf

    set_webui_setting() {
      local key="$1"
      local value="$2"
      local temp_file
      temp_file="$(mktemp "$config_file.XXXXXX")"

      KEY="$key" VALUE="$value" awk '
        BEGIN {
          key = ENVIRON["KEY"]
          value = ENVIRON["VALUE"]
          in_webui = 0
          found = 0
        }
        /^\[WebUI\]$/ {
          in_webui = 1
          print
          next
        }
        /^\[/ {
          if (in_webui && !found) {
            print key "=" value
            found = 1
          }
          in_webui = 0
        }
        {
          if (in_webui && index($0, key "=") == 1) {
            if (!found) {
              print key "=" value
              found = 1
            }
            next
          }
          print
        }
        END {
          if (in_webui && !found) {
            print key "=" value
            found = 1
          }
          if (!found) {
            print ""
            print "[WebUI]"
            print key "=" value
          }
        }
      ' "$config_file" >"$temp_file"

      chown --reference="$config_file" "$temp_file"
      chmod --reference="$config_file" "$temp_file"
      mv "$temp_file" "$config_file"
    }

    if [[ "${var.webui_auth_enabled}" == "true" ]]; then
      set_webui_setting 'AuthSubnetWhitelistEnabled' 'false'
    else
      set_webui_setting 'AuthSubnetWhitelist' '0.0.0.0/0, ::/0'
      set_webui_setting 'AuthSubnetWhitelistEnabled' 'true'
    fi
  EOT
}

resource "docker_image" "qbittorrent" {
  name         = "lscr.io/linuxserver/qbittorrent:5.3.0@sha256:3d4c4545d51a690a0df15a2ff99038823a88a9822df8e794526447b9afbd7384"
  platform     = "linux/${var.zp_arch}"
  keep_locally = true
}

resource "docker_container" "qbittorrent_main" {
  name  = "${var.zp_module_id}-main"
  image = docker_image.qbittorrent.image_id

  networks_advanced {
    name = var.zp_network_name
  }

  restart = "unless-stopped"

  env = [
    "PUID=${var.puid}",
    "PGID=${var.pgid}",
    "TZ=${var.timezone}",
    "WEBUI_PORT=8080",
    "TORRENTING_PORT=${var.torrenting_port}",
  ]

  volumes {
    host_path      = "${var.zp_storage_dir}/config"
    container_path = "/config"
    read_only      = false
  }

  volumes {
    host_path      = local.media_path
    container_path = "/media"
    read_only      = false
  }

  upload {
    content    = local.webui_auth_init_script
    file       = "/custom-cont-init.d/10-webui-auth.sh"
    executable = true
  }

  ports {
    internal = var.torrenting_port
    external = var.torrenting_port
    protocol = "udp"
  }

  ports {
    internal = var.torrenting_port
    external = var.torrenting_port
    protocol = "tcp"
  }
}

output "main" {
  value       = docker_container.qbittorrent_main
  description = "Main qBittorrent container"
}

output "main_ports" {
  value = {
    webui = {
      port        = 8080
      protocol    = "http"
      transport   = "tcp"
      description = "qBittorrent web interface"
      default     = true
    }
  }
  description = "Web UI service exposed through Zeropoint"
}

output "webui_url" {
  value       = "http://${docker_container.qbittorrent_main.name}:8080"
  description = "qBittorrent web interface URL accessible via Docker network"
}
