variable "bucket_name" {
  description = "Nombre del bucket de logs (único a nivel global; incluye la cuenta)."
  type        = string
}

variable "retention_days" {
  description = "Días tras los cuales S3 borra los objetos. Red de seguridad: debe superar la retención de Loki, que es la que decide qué se ve."
  type        = number
  default     = 14

  validation {
    condition     = var.retention_days >= 2
    error_message = "retention_days must be at least 2 days."
  }
}

variable "force_destroy" {
  description = "Permite borrar el bucket con objetos. Solo true en staging bajo demanda, que guarda logs sintéticos."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Clúster EKS al que pertenece la cuenta de servicio de Loki."
  type        = string
}

variable "namespace" {
  description = "Namespace de Loki."
  type        = string
  default     = "monitoring"
}

variable "service_account" {
  description = "Cuenta de servicio de Kubernetes de Loki que accede al bucket."
  type        = string
  default     = "loki"
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
