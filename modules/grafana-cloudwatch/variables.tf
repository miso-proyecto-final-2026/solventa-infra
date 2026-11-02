variable "cluster_name" {
  description = "Nombre del clúster EKS al que se asocia la identidad."
  type        = string
}

variable "namespace" {
  description = "Namespace de Grafana."
  type        = string
  default     = "monitoring"
}

variable "service_account" {
  description = "Cuenta de servicio de Grafana. Debe coincidir con la que crea el chart."
  type        = string
  default     = "grafana"
}

variable "tags" {
  description = "Etiquetas comunes."
  type        = map(string)
  default     = {}
}
