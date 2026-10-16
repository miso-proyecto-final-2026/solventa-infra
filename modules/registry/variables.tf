variable "repositories" {
  description = "Nombres de los repositorios ECR (uno por servicio)."
  type        = set(string)
}

variable "keep_tagged_images" {
  description = "Número de imágenes etiquetadas a conservar."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
