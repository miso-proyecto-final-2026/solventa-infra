variable "services" {
  description = "Mapa nombre de servicio => { role_name }. Un secreto de BD por servicio."
  type = map(object({
    role_name = string
  }))
}

variable "db_host" {
  description = "Host de PostgreSQL."
  type        = string
}

variable "db_port" {
  description = "Puerto de PostgreSQL."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Nombre de la base de datos."
  type        = string
  default     = "solventa"
}

variable "cache_host" {
  description = "Host primario de la caché."
  type        = string
}

variable "cache_port" {
  description = "Puerto de la caché."
  type        = number
  default     = 6379
}

variable "cache_auth_token" {
  description = "Token de autenticación de la caché."
  type        = string
  sensitive   = true
}

variable "secret_prefix" {
  description = "Prefijo de los nombres en Secrets Manager."
  type        = string
  default     = "solventa/staging"
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
