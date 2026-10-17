variable "bucket_name" {
  description = "Nombre del bucket (único a nivel global; incluye la cuenta)."
  type        = string
}

variable "retention_days" {
  description = "Días que se conservan las evidencias antes de expirar (retención de datos KYC)."
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "force_destroy" {
  description = "Permite borrar el bucket con objetos. Solo true en staging bajo demanda, que guarda evidencias sintéticas."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Clúster EKS al que pertenece la cuenta de servicio autorizada."
  type        = string
}

variable "namespace" {
  description = "Namespace de la cuenta de servicio autorizada a escribir."
  type        = string
  default     = "staging"
}

variable "service_account" {
  description = "Cuenta de servicio de Kubernetes (igual al nombre del servicio) autorizada a escribir evidencias."
  type        = string
}

variable "prefix" {
  description = "Prefijo de las claves donde se permite escribir."
  type        = string
  default     = "kyc/"
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
