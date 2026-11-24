variable "env_name" {
  description = "Environment name, used in the container name (webapp-<env_name>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.env_name))
    error_message = "env_name must contain only lowercase letters, digits and dashes."
  }
}

variable "image" {
  description = "Container image to run, with an explicit tag (for example nginx:1.27)."
  type        = string
}

variable "external_port" {
  description = "Host port mapped to port 80 of the container. Must be unique per environment."
  type        = number

  validation {
    condition     = var.external_port >= 1024 && var.external_port <= 65535
    error_message = "external_port must be between 1024 and 65535."
  }
}
