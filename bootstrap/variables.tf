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

variable "github_ids" {
  description = "IDs de GitHub (no secretos) para el subject OIDC inmutable: organización y cada repositorio con rol. Ver modules/ci-identities."
  type = object({
    organization_id = string
    repositories    = map(string)
  })
  default = {
    organization_id = "313182026"
    repositories = {
      "miso-proyecto-final-2026/solventa-infra"   = "1412530280"
      "miso-proyecto-final-2026/solventa-backend" = "1412524586"
      "miso-proyecto-final-2026/solventa-web"     = "1412528255"
    }
  }
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

variable "web_repository" {
  description = "Repositorio GitHub (owner/repo) de la consola web: recibe su rol de despliegue (HU39)."
  type        = string
  default     = "miso-proyecto-final-2026/solventa-web"
}
