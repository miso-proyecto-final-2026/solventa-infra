variable "name" {
  description = "Nombre del clúster MSK."
  type        = string
  default     = "solventa-staging-events"
}

variable "cluster_name" {
  description = "Clúster EKS al que se asocian las identidades de los pods (Pod Identity)."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde vive el clúster."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas, una por zona de disponibilidad."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Único security group con acceso al puerto 9098 (nodos EKS)."
  type        = string
}

variable "kafka_version" {
  description = "Versión de Kafka. Con .kraft no hay ZooKeeper; si el tipo de broker no la admite, usar la variante con ZooKeeper (por ejemplo 3.8.x)."
  type        = string
  default     = "3.9.x.kraft"
}

variable "broker_node_type" {
  description = "Tipo de broker. kafka.t3.small es el más barato y basta para staging."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_count" {
  description = "Brokers del clúster: múltiplo del número de subredes (uno por zona como mínimo)."
  type        = number
  default     = 2

  validation {
    condition     = var.broker_count >= 2 && var.broker_count % length(var.subnet_ids) == 0
    error_message = "broker_count debe ser al menos 2 y múltiplo del número de subredes (un broker por zona como mínimo)."
  }
}

variable "ebs_volume_size_gb" {
  description = "Disco de cada broker, en GiB."
  type        = number
  default     = 10
}

variable "access" {
  description = <<-EOT
    Permisos mínimos por servicio sobre el bus. La clave es el nombre del servicio (también el prefijo de sus grupos de
    consumo). `produce` y `consume` son listas de topics; quien consume puede además escribir en la cola de mensajes
    fallidos (`<topic>.dlq`) de lo que consume. La identidad se vincula a la cuenta de servicio de Kubernetes indicada.
  EOT
  type = map(object({
    namespace       = string
    service_account = string
    produce         = optional(list(string), [])
    consume         = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for s in values(var.access) : [
        for t in concat(s.produce, s.consume) : can(regex("^[a-zA-Z0-9._-]{1,200}$", t))
      ]
    ]))
    error_message = "Los topics solo admiten letras, dígitos, punto, guion y guion bajo (sin comodines)."
  }
}

variable "admin_namespace" {
  description = "Namespace de la cuenta de servicio que crea los topics."
  type        = string
  default     = "solventa-system"
}

variable "admin_service_account" {
  description = "Cuenta de servicio del Job que crea los topics."
  type        = string
  default     = "kafka-topics"
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
