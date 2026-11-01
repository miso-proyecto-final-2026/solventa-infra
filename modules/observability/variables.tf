variable "namespace" {
  description = "Namespace donde se instalan Grafana, Loki y Alloy (el mismo de Prometheus)."
  type        = string
  default     = "monitoring"
}

variable "log_namespaces" {
  description = "Namespaces de los que Alloy recoge los logs de los pods."
  type        = list(string)
  default     = ["staging"]

  validation {
    condition     = length(var.log_namespaces) > 0
    error_message = "Debe haber al menos un namespace de logs."
  }
}

variable "prometheus_url" {
  description = "URL del Prometheus del clúster que Grafana usa como fuente de métricas."
  type        = string
  default     = "http://prometheus-server.monitoring.svc"
}

variable "log_retention" {
  description = "Cuánto conserva Loki los logs. null = 48h en el disco del nodo (se pierden si el pod se reinicia) o 168h si hay bucket de logs."
  type        = string
  default     = null
}

variable "logs_bucket" {
  description = "Bucket S3 donde Loki guarda chunks e índice (lo crea modules/logs-storage). null = disco efímero del nodo."
  type        = string
  default     = null
}

variable "logs_bucket_region" {
  description = "Región del bucket de logs. Obligatoria si hay bucket."
  type        = string
  default     = null

  validation {
    condition     = var.logs_bucket == null || var.logs_bucket_region != null
    error_message = "logs_bucket_region is required when logs_bucket is set."
  }
}

variable "loki_service_account" {
  description = "Cuenta de servicio de Loki. Debe coincidir con la que autoriza el rol de Pod Identity del bucket."
  type        = string
  default     = "loki"
}

variable "loki_storage_limit" {
  description = "Tope del disco efímero de Loki (con bucket solo guarda el WAL y la caché del índice). Si lo supera, Kubernetes desaloja el pod."
  type        = string
  default     = "3Gi"
}

variable "grafana_chart_version" {
  description = "Versión del chart grafana (grafana-community)."
  type        = string
  default     = "13.6.0"
}

variable "loki_chart_version" {
  description = "Versión del chart loki (grafana)."
  type        = string
  default     = "7.3.0"
}

variable "alloy_chart_version" {
  description = "Versión del chart alloy (grafana)."
  type        = string
  default     = "1.13.1"
}
