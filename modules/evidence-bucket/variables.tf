variable "bucket_name" {
  description = "Nombre del bucket (único a nivel global; incluye la cuenta)."
  type        = string
}

variable "retention_days" {
  description = "Días que se conservan los objetos antes de expirar (retención de datos KYC). null = no expiran (documentos de póliza)."
  type        = number
  default     = 90
  nullable    = true

  validation {
    condition     = var.retention_days == null ? true : var.retention_days >= 1
    error_message = "retention_days must be null (no expiration) or at least 1."
  }
}

variable "noncurrent_days" {
  description = "Días que se conservan las versiones antiguas de un objeto sobrescrito."
  type        = number
  default     = 1

  validation {
    condition     = var.noncurrent_days >= 1
    error_message = "noncurrent_days must be at least 1."
  }
}

variable "existing_role_name" {
  description = "Rol de Pod Identity que el servicio ya asume (p. ej. el de MSK). Si se da, no se crea rol ni asociación: la política de escritura se adjunta a ese rol. null = crear el rol del bucket."
  type        = string
  default     = null
}

variable "policy_name" {
  description = "Nombre de la política en línea de escritura. Distinto por bucket cuando comparten rol."
  type        = string
  default     = "write-evidencias"
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
