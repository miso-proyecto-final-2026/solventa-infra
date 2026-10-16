variable "name" {
  description = "Identificador de la instancia."
  type        = string
  default     = "solventa-staging-postgres"
}

variable "vpc_id" {
  description = "VPC donde vive la base de datos."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas del grupo de subredes."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Único security group con acceso al puerto 5432 (nodos EKS, FR-007)."
  type        = string
}

variable "instance_class" {
  description = "Clase de instancia."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Almacenamiento gp3 en GiB."
  type        = number
  default     = 20
}

variable "engine_version" {
  description = "Versión mayor de PostgreSQL."
  type        = string
  default     = "16"
}

variable "multi_az" {
  description = "Despliegue Multi-AZ (FR-012)."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Días de retención de respaldos (mínimo 7 en staging, FR-012)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "backup_retention_days must be at least 7 (FR-012)."
  }
}

variable "deletion_protection" {
  description = "Protección contra borrado (false por defecto para teardown bajo demanda, FR-017)."
  type        = bool
  default     = false
}

variable "final_snapshot_enabled" {
  description = "Tomar snapshot final al destruir (false por defecto, FR-017)."
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Nombre de la base de datos compartida."
  type        = string
  default     = "solventa"
}

variable "admin_username" {
  description = "Usuario administrador (la contraseña la gestiona RDS en Secrets Manager)."
  type        = string
  default     = "solventa_admin"
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
