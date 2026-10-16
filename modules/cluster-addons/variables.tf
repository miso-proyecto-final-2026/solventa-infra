variable "secret_store" {
  description = <<-EOT
    Origen de los secretos que sincroniza External Secrets Operator.
    - kind = "aws": AWS Secrets Manager (credenciales por Pod Identity), requiere region.
    - kind = "kubernetes": Secrets de un namespace del propio clúster (kind local), requiere namespace.
  EOT

  type = object({
    kind      = string
    region    = optional(string, "us-east-1")
    namespace = optional(string, "local-secrets")
    name      = optional(string, "solventa")
  })

  validation {
    condition     = contains(["aws", "kubernetes"], var.secret_store.kind)
    error_message = "secret_store.kind must be \"aws\" or \"kubernetes\"."
  }
}

variable "metrics_server_args" {
  description = "Argumentos extra de metrics-server (en kind: [\"--kubelet-insecure-tls\"])."
  type        = list(string)
  default     = []
}

variable "staging_namespace" {
  description = "Namespace de las cargas de trabajo."
  type        = string
  default     = "staging"
}

variable "system_namespace" {
  description = "Namespace de componentes de plataforma (Job db-access)."
  type        = string
  default     = "solventa-system"
}

variable "eso_namespace" {
  description = "Namespace de External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "deployers_group" {
  description = "Grupo de Kubernetes de los pipelines de despliegue."
  type        = string
  default     = "solventa-deployers"
}

variable "metrics_server_chart_version" {
  description = "Versión del chart metrics-server."
  type        = string
  default     = "3.13.0"
}

variable "external_secrets_chart_version" {
  description = "Versión del chart external-secrets."
  type        = string
  default     = "2.12.0"
}
