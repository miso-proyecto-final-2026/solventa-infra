variable "cluster_name" {
  description = "Nombre del clúster."
  type        = string
  default     = "solventa-staging"
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes; debe estar en soporte estándar de EKS (research R5)."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC del clúster."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas para nodos y plano de control."
  type        = list(string)
}

variable "api_allowed_cidrs" {
  description = "CIDR con acceso al endpoint público de la API (FR-011a)."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs must contain valid CIDR blocks."
  }
}

variable "cluster_admin_principal_arns" {
  description = "Principales IAM con permisos de administrador del clúster (FR-011); solo ARN de IAM."
  type        = list(string)

  validation {
    condition     = length(var.cluster_admin_principal_arns) >= 1 && alltrue([for a in var.cluster_admin_principal_arns : startswith(a, "arn:aws:iam::")])
    error_message = "cluster_admin_principal_arns needs at least one IAM ARN (FR-011)."
  }
}

variable "plan_role_arn" {
  description = "ARN del rol de plan de CI (acceso de solo lectura al clúster); null para omitir."
  type        = string
  default     = null
}

variable "deployer_role_arns" {
  description = "Mapa servicio => ARN del rol de despliegue; entran al grupo Kubernetes solventa-deployers."
  type        = map(string)
  default     = {}
}

variable "deployers_group" {
  description = "Grupo de Kubernetes asociado por RoleBinding en el namespace staging."
  type        = string
  default     = "solventa-deployers"
}

variable "node_instance_type" {
  description = "Tipo de instancia de los nodos."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Número de nodos (mínimo = az_count)."
  type        = number
  default     = 3
}

variable "node_max_count" {
  description = "Máximo de nodos del grupo gestionado."
  type        = number
  default     = 4
}

variable "node_disk_size_gib" {
  description = "Tamaño del disco gp3 de cada nodo."
  type        = number
  default     = 20
}

variable "enable_control_plane_logging" {
  description = "Activa los logs del plano de control (crea un log group gestionado por Terraform)."
  type        = bool
  default     = false
}

variable "eso_namespace" {
  description = "Namespace de External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account" {
  description = "ServiceAccount de External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "secrets_prefix" {
  description = "Prefijo de los secretos que ESO puede leer."
  type        = string
  default     = "solventa/staging"
}

variable "db_admin_secret_arn" {
  description = "ARN del secreto maestro de RDS que ESO puede leer; null si aún no existe."
  type        = string
  default     = null
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
