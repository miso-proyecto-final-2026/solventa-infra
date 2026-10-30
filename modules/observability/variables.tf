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
  description = "Cuánto conserva Loki los logs. Se guardan en el disco del nodo (emptyDir): se pierden si el pod de Loki se reinicia."
  type        = string
  default     = "48h"
}

variable "loki_storage_limit" {
  description = "Tope del disco efímero de Loki. Si lo supera, Kubernetes desaloja el pod: la retención debe mantenerlo muy por debajo."
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
