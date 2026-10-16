variable "region" {
  description = "Región AWS."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Nombre del bucket de estado. Si es null: solventa-tfstate-<cuenta>-<región>."
  type        = string
  default     = null
}

variable "infra_repository" {
  description = "Repositorio GitHub (owner/repo) de la infraestructura."
  type        = string
  default     = "miso-proyecto-final-2026/solventa-infra"
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub; false si la cuenta ya tiene uno."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Nombre del clúster EKS al que apuntan las políticas de los roles."
  type        = string
  default     = "solventa-staging"
}
