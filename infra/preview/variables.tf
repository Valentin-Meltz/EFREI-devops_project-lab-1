variable "pr_number" {
  description = "Pull Request number; the namespace is pr-<pr_number>."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.pr_number))
    error_message = "pr_number must be a Pull Request number (digits only)."
  }
}

variable "image" {
  description = "Image to preview, pinned to a tag or digest (the commit SHA of the PR), never :latest."
  type        = string

  validation {
    condition     = can(regex("[:@][^/]+$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must carry an explicit tag or digest other than latest."
  }
}

variable "owner" {
  description = "Who is responsible for the preview (for example the PR author); a namespace label."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$", var.owner))
    error_message = "owner must be a valid Kubernetes label value (63 characters max, letters, digits, '-', '_', '.')."
  }
}

variable "ttl_days" {
  description = "Days until the preview expires; written once to the expires label."
  type        = number
  default     = 3

  validation {
    condition     = var.ttl_days >= 1 && var.ttl_days <= 14
    error_message = "ttl_days must be between 1 and 14."
  }
}

variable "kube_context" {
  description = "kubeconfig context of the cluster that hosts the previews."
  type        = string
  default     = "kind-devops-lab"
}

variable "ghcr_user" {
  description = "GitHub user that owns the GHCR pull token."
  type        = string
  default     = "Valentin-Meltz"
}

variable "ghcr_token" {
  description = "GHCR token with the read:packages scope. Pass it as TF_VAR_ghcr_token; it is never stored."
  type        = string
  sensitive   = true
  ephemeral   = true
}
