variable "bootstrap_servers" {
  description = "Brokers de MSK (SASL/IAM, puerto 9098), separados por coma."
  type        = string

  validation {
    condition     = length(trimspace(var.bootstrap_servers)) > 0
    error_message = "bootstrap_servers is required."
  }
}

variable "region" {
  description = "Región de AWS del clúster (para firmar la autenticación IAM)."
  type        = string
}

variable "topics" {
  description = "Topics a crear, por nombre. `dlq` crea además <topic>.dlq con una partición."
  type = map(object({
    partitions      = number
    retention_hours = number
    dlq             = bool
  }))
}

variable "namespace" {
  description = "Namespace del Job y de su cuenta de servicio."
  type        = string
  default     = "solventa-system"
}

variable "service_account" {
  description = "Cuenta de servicio con el rol de Pod Identity que puede crear topics."
  type        = string
  default     = "kafka-topics"
}

variable "replication_factor" {
  description = "Factor de replicación (dos brokers)."
  type        = number
  default     = 2
}

variable "image" {
  description = "Imagen con Python para ejecutar el script."
  type        = string
  default     = "python:3.12-slim"
}

variable "job_timeout" {
  description = "Tiempo máximo para que el Job termine."
  type        = string
  default     = "10m"
}
