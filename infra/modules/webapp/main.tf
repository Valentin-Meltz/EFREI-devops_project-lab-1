# A module that uses a provider outside the hashicorp/ namespace must declare
# it, otherwise Terraform looks for hashicorp/docker. The provider itself is
# configured by the calling root module (infra/envs/<env>).
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

resource "docker_image" "app" {
  name = var.image
  # Every environment runs on the same Docker host and may use the same image:
  # destroying one environment must not try to delete an image another one
  # still uses.
  keep_locally = true
}

resource "docker_container" "web" {
  name  = "webapp-${var.env_name}"
  image = docker_image.app.image_id

  ports {
    internal = 80
    external = var.external_port
  }
}
