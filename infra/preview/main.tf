# Ephemeral preview environment: one namespace pr-<number> per Pull Request,
# running the Session 2 application. Each PR has its own state file:
#   terraform init -reconfigure -backend-config="path=state/pr-<number>.tfstate"
# (-reconfigure: switching PRs must never migrate one PR's state into another's).
terraform {
  backend "local" {}

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  # Pinned, so a preview can never land on whatever context is current.
  config_context = var.kube_context
}

locals {
  namespace = "pr-${var.pr_number}"
  app       = { app = "myapp" }
  # Stamped when the namespace is created (see ignore_changes below).
  expires = formatdate("YYYY-MM-DD", timeadd(plantimestamp(), "${var.ttl_days * 24}h"))
}

resource "kubernetes_namespace" "preview" {
  metadata {
    name = local.namespace
    labels = {
      purpose = "preview"
      pr      = var.pr_number
      # Cost control (4.5): who to ask, and when it may be deleted.
      owner   = var.owner
      expires = local.expires
    }
  }

  lifecycle {
    # The expiry date is set once, at creation; later plans must not move it.
    ignore_changes = [metadata[0].labels["expires"]]
  }
}

# The GHCR package is private, and the kubelet only lets a pod use an image
# pulled with credentials if the pod has credentials too. The token is a
# write-only argument fed by an ephemeral variable: it is sent to Kubernetes
# but never written to the plan or the state.
resource "kubernetes_secret" "ghcr_pull" {
  metadata {
    name      = "ghcr-pull"
    namespace = kubernetes_namespace.preview.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data_wo = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_user}:${var.ghcr_token}")
        }
      }
    })
  }
  # Write-only values are not compared between runs: increase this number to
  # push a rotated token.
  data_wo_revision = 1
}

resource "kubernetes_deployment" "app" {
  # Checkov cannot see through var.image; both points are enforced elsewhere.
  #checkov:skip=CKV_K8S_14:var.image validation rejects :latest and untagged images
  #checkov:skip=CKV_K8S_43:tags are full commit SHAs, never reused (docs/image-registry.md)
  metadata {
    name      = "myapp"
    namespace = kubernetes_namespace.preview.metadata[0].name
    labels    = local.app
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.app
    }

    template {
      metadata {
        labels = local.app
      }

      spec {
        automount_service_account_token = false

        image_pull_secrets {
          name = kubernetes_secret.ghcr_pull.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 1000 # "node" in the image; must be numeric for run_as_non_root
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "myapp"
          image = var.image
          # Always: every new pod authenticates to the registry with its own
          # pull secret, even when the image is already cached on the node.
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "APP_ENV"
            value = local.namespace
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          security_context {
            # DELIBERATE MISCONFIGURATION (Lab 3, part 5.5), reverted next:
            # a privileged container that may escalate privileges.
            privileged                 = true
            allow_privilege_escalation = true
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }

  # A preview that cannot start should fail the pipeline quickly.
  timeouts {
    create = "3m"
    update = "3m"
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "myapp"
    namespace = kubernetes_namespace.preview.metadata[0].name
    labels    = local.app
  }

  spec {
    type     = "ClusterIP"
    selector = local.app

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }
}
