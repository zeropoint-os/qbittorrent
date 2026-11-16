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
  description = "Pre-created Docker network name for this module (managed by zeropoint)"
}

variable "zp_arch" {
  type        = string
  default     = "amd64"
  description = "Target architecture - amd64, arm64, etc. (injected by zeropoint)"
}

variable "zp_gpu_vendor" {
  type        = string
  default     = ""
  description = "GPU vendor - unused by this module (injected by zeropoint)"
}

variable "zp_module_dir" {
  type        = string
  description = "Agent's working directory for this module (injected by zeropoint)"
}

variable "zp_storage_dir" {
  type        = string
  description = "Isolated data root for this module; all bind mounts must live under this path"
}

resource "docker_image" "qbittorrent" {
  name = "${var.zp_module_id}:latest"
  build {
    context    = path.module
    dockerfile = "Dockerfile"
    platform   = "linux/${var.zp_arch}"
  }
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
    "PUID=1000",
    "PGID=1000",
    "TZ=Etc/UTC",
    "WEBUI_PORT=8080",
    "TORRENTING_PORT=6881",
  ]

  volumes {
    host_path      = "${var.zp_storage_dir}/config"
    container_path = "/config"
  }

  volumes {
    host_path      = "${var.zp_storage_dir}/downloads"
    container_path = "/downloads"
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
    torrent_tcp = {
      port        = 6881
      protocol    = "tcp"
      transport   = "tcp"
      description = "BitTorrent peer connections over TCP"
      default     = false
    }
    torrent_udp = {
      port        = 6881
      protocol    = "udp"
      transport   = "udp"
      description = "BitTorrent peer connections and DHT over UDP"
      default     = false
    }
  }
  description = "Service ports for external access"
}

output "webui_url" {
  value       = "http://${docker_container.qbittorrent_main.name}:8080"
  description = "qBittorrent web interface URL accessible via Docker network"
}
