variable "region" {
  description = "Región AWS."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Nombre del entorno (prefijo solventa-<name>)."
  type        = string
  default     = "staging"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.name))
    error_message = "name must match ^[a-z][a-z0-9-]{1,15}$."
  }
}

variable "az_count" {
  description = "Número de zonas de disponibilidad (mínimo 2, FR-006)."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "one_nat_gateway_per_az" {
  description = "Un NAT gateway por AZ (más costo, más independencia entre AZ)."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Versión de Kubernetes (debe estar en soporte estándar de EKS)."
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "Tipo de instancia de los nodos."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "Número de nodos (mínimo az_count)."
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= var.az_count
    error_message = "node_count must be at least az_count."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDR con acceso al endpoint público de la API (FR-011a). Restringirlo a la IP del equipo en cuanto sea posible."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_principal_arns" {
  description = "Principales IAM adicionales con rol de administrador del clúster; el rol de apply de CI siempre se incluye (FR-011)."
  type        = list(string)
  default     = []
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "RDS Multi-AZ (FR-012)."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "Días de retención de respaldos (mínimo 7, FR-012)."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Protección contra borrado de RDS (false por defecto, FR-017)."
  type        = bool
  default     = false
}

variable "db_final_snapshot" {
  description = "Snapshot final de RDS al destruir (false por defecto, FR-017)."
  type        = bool
  default     = false
}

variable "cache_node_type" {
  description = "Tipo de nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_engine" {
  description = "Motor de caché: redis o valkey (FR-018)."
  type        = string
  default     = "redis"
}

variable "cache_replicas" {
  description = "Réplicas de la caché (mínimo 1, FR-018)."
  type        = number
  default     = 1
}

variable "enable_control_plane_logging" {
  description = "Logs del plano de control de EKS (genera un log group gestionado)."
  type        = bool
  default     = false
}

variable "enable_edge" {
  description = "Crear el borde público (CloudFront + WAF, API Gateway y NLB). Sin él los servicios solo son internos."
  type        = bool
  default     = true
}

variable "edge_allowed_countries" {
  description = "Países permitidos por el WAF (ISO 3166-1 alfa-2); el resto se bloquea."
  type        = list(string)
  default     = ["CO", "US"]
}

variable "edge_rate_limit_per_5min" {
  description = "Máximo de solicitudes por IP en 5 minutos antes de responder 429 en el WAF."
  type        = number
  default     = 1000
}

variable "edge_throttling_rate_limit" {
  description = "Solicitudes por segundo sostenidas que admite el API Gateway."
  type        = number
  default     = 200
}

variable "edge_throttling_burst_limit" {
  description = "Ráfaga máxima del API Gateway."
  type        = number
  default     = 400
}

variable "edge_high_volume_rate_limit_per_5min" {
  description = "Máximo de solicitudes por IP en 5 minutos en las rutas `high_volume` (proveedores de eventos) antes del 429 del WAF."
  type        = number
  default     = 600000 # ≈ 2.000 solicitudes por segundo desde una misma IP; la meta EC-E2.1 son ≈ 1.670/s
}

variable "edge_high_volume_throttling_rate_limit" {
  description = "Solicitudes por segundo sostenidas por ruta `high_volume` en el API Gateway."
  type        = number
  default     = 2000
}

variable "edge_high_volume_throttling_burst_limit" {
  description = "Ráfaga máxima por ruta `high_volume` en el API Gateway."
  type        = number
  default     = 4000
}

variable "enable_events" {
  description = "Crear el bus de eventos (MSK, HS2). Factura por hora y tarda ~25 min en crearse: apagarlo si la sesión no usa eventos."
  type        = bool
  default     = true
}

variable "events_broker_type" {
  description = "Tipo de broker de MSK. kafka.t3.small es el más barato."
  type        = string
  default     = "kafka.t3.small"
}

variable "events_kafka_version" {
  description = "Versión de Kafka. Si el tipo de broker no admite KRaft, usar la variante con ZooKeeper (por ejemplo 3.8.x)."
  type        = string
  default     = "3.9.x.kraft"
}
