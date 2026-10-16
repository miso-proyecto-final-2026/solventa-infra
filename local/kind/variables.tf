variable "kubeconfig_path" {
  description = "Ruta del kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto de kubectl del clúster kind."
  type        = string
  default     = "kind-solventa"
}

variable "services_file" {
  description = "Lista de servicios (services.yaml o services.extra.yaml), relativa a local/kind."
  type        = string
  default     = "services.yaml"
}
