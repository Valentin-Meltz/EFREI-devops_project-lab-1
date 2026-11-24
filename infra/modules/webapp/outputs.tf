output "app_url" {
  description = "URL of the environment on the Docker host."
  value       = "http://localhost:${var.external_port}"
}

output "container_name" {
  description = "Name of the container created for this environment."
  value       = docker_container.web.name
}
