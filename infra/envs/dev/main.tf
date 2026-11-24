terraform {
  # Partial backend configuration: the state location is given at init time,
  #   terraform init -backend-config=shared.backend.hcl
  # (shared folder, see part 3.3). Without it, the state stays in this folder.
  backend "local" {}

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "env_name" { type = string }
variable "image" { type = string }
variable "external_port" { type = number }

module "webapp" {
  source        = "../../modules/webapp"
  env_name      = var.env_name
  image         = var.image
  external_port = var.external_port
}

output "app_url" {
  value = module.webapp.app_url
}

output "container_name" {
  value = module.webapp.container_name
}
