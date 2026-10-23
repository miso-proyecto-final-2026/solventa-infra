variable "services" {
  description = "Servicios normalizados (salida services de modules/service-list)."
  type = map(object({
    image_tag   = string
    port        = number
    health_path = string
    resources = object({
      requests = object({ cpu = string, memory = string })
      limits   = object({ cpu = string, memory = string })
    })
    replicas          = object({ min = number, max = number })
    autoscaling       = optional(object({ cpu_target_percent = optional(number, 70) }), {})
    owned_schemas     = list(string)
    database_env_vars = optional(list(string), ["DATABASE_URL"])
    cache_env_var     = optional(string)
    settings          = optional(map(string), {})
    secret_env_vars   = optional(map(string), {})
    migration_command = optional(list(string))
    run_as_non_root   = optional(bool, false)
    role_name         = string
    edge = optional(object({
      node_port     = number
      path_prefixes = list(string)
    }))
  }))
}

variable "reserved_schemas" {
  description = "Esquemas reservados sin dueño."
  type        = list(string)
  default     = []
}

variable "drop_schemas" {
  description = "Esquemas a eliminar de forma explícita (solo si no tienen dueño)."
  type        = list(string)
  default     = []
}

variable "image_registry" {
  description = "Registro de imágenes (vacío en kind, donde las imágenes se cargan con kind load)."
  type        = string
  default     = ""
}

variable "secret_store" {
  description = "Origen de secretos: { kind = aws|kubernetes, region, namespace, name }."
  type = object({
    kind      = string
    region    = optional(string, "us-east-1")
    namespace = optional(string, "local-secrets")
    name      = optional(string, "solventa")
  })
}

variable "db" {
  description = "Base de datos: host, referencia del secreto del administrador y sslmode."
  type = object({
    host             = string
    port             = optional(number, 5432)
    name             = optional(string, "solventa")
    admin_secret_ref = string
    sslmode          = optional(string, "require")
  })
}

variable "cache" {
  description = "Caché: scheme (rediss|redis), host, puerto y secret_ref (null si no hay token)."
  type = object({
    scheme     = string
    host       = string
    port       = optional(number, 6379)
    secret_ref = optional(string)
  })
}

variable "service_db_secret_names" {
  description = "Mapa servicio => nombre del secreto de BD."
  type        = map(string)
}

variable "service_db_secret_versions" {
  description = "Mapa servicio => version_id del secreto (entrada del hash del Job db-access)."
  type        = map(string)
  default     = {}
}

variable "metrics_server_args" {
  description = "Argumentos extra de metrics-server."
  type        = list(string)
  default     = []
}

variable "staging_namespace" {
  description = "Namespace de las cargas."
  type        = string
  default     = "staging"
}

variable "system_namespace" {
  description = "Namespace de componentes de plataforma."
  type        = string
  default     = "solventa-system"
}

variable "events" {
  description = "Bus de eventos (HS2). null si la plataforma no lo tiene (kind, o enable_events = false): no se crean los topics."
  type = object({
    bootstrap_servers = string
    region            = string
    topics = map(object({
      partitions      = number
      retention_hours = number
      dlq             = bool
    }))
  })
  default = null
}
