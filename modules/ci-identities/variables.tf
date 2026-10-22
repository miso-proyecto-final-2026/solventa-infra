variable "infra_repository" {
  description = "Repositorio GitHub (owner/repo) de la infraestructura; confía en sus workflows de plan y apply."
  type        = string
  default     = "miso-proyecto-final-2026/solventa-infra"
}

variable "deploy_repositories" {
  description = "Mapa servicio => repositorio GitHub (owner/repo) que recibe un rol de despliegue."
  type        = map(string)
}

variable "github_ids" {
  description = <<-EOT
    IDs numéricos de GitHub para el subject OIDC inmutable (`repo:<owner>@<id-org>/<repo>@<id-repo>:...`), que GitHub
    emite cuando el repositorio tiene `use_immutable_subject`. `repositories` va por `owner/repo`. No son secretos:
    se obtienen con `gh api orgs/<owner> --jq .id` y `gh api repos/<owner>/<repo> --jq .id`.
  EOT
  type = object({
    organization_id = string
    repositories    = map(string)
  })

  validation {
    condition     = can(regex("^[0-9]+$", var.github_ids.organization_id)) && alltrue([for id in values(var.github_ids.repositories) : can(regex("^[0-9]+$", id))])
    error_message = "Los IDs de GitHub deben ser numéricos."
  }

  validation {
    condition     = alltrue([for r in concat([var.infra_repository], values(var.deploy_repositories)) : contains(keys(var.github_ids.repositories), r)])
    error_message = "github_ids.repositories debe traer el ID de infra_repository y de cada repositorio de deploy_repositories."
  }
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub. Poner false si la cuenta ya tiene uno."
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Nombre del bucket S3 de estado de Terraform."
  type        = string
}

variable "cluster_name" {
  description = "Nombre del clúster EKS (determinista, por eso las políticas son válidas antes de que exista)."
  type        = string
  default     = "solventa-staging"
}

variable "environment_name" {
  description = "Nombre del GitHub environment que respalda los roles de apply y deploy."
  type        = string
  default     = "staging"
}

variable "max_session_duration" {
  description = "Duración máxima de sesión de los roles, en segundos."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005)."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}

variable "attach_managed_policies" {
  description = "Adjuntar ReadOnlyAccess y PowerUserAccess. Poner false solo en el emulador Moto, que no precarga políticas gestionadas por AWS."
  type        = bool
  default     = true
}
