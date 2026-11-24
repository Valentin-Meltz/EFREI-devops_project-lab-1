output "namespace" {
  value = kubernetes_namespace.preview.metadata[0].name
}

output "expires" {
  value = kubernetes_namespace.preview.metadata[0].labels["expires"]
}

output "service_url" {
  description = "URL of the preview inside the cluster."
  value       = "http://${kubernetes_service.app.metadata[0].name}.${kubernetes_namespace.preview.metadata[0].name}.svc.cluster.local"
}

output "port_forward" {
  description = "Command to reach the preview from this machine on http://localhost:8080."
  value       = "kubectl --context ${var.kube_context} port-forward -n ${kubernetes_namespace.preview.metadata[0].name} svc/${kubernetes_service.app.metadata[0].name} 8080:80"
}
