variable "name" {
  description = "Nombre del servicio (Deployment, Service, repositorio)."
  type        = string
}

variable "service" {
  description = "Entrada normalizada del servicio (contrato C1)."
  type = object({
    image_tag   = string
    port        = number
    health_path = string
    resources = object({
      requests = object({ cpu = string, memory = string })
      limits   = object({ cpu = string, memory = string })
    })
    replicas    = object({ min = number, max = number })
    autoscaling = optional(object({ cpu_target_percent = optional(number, 70) }), {})
    edge = optional(object({
      node_port     = number
      path_prefixes = list(string)
    }))
    database_env_vars = optional(list(string), ["DATABASE_URL"])
    cache_env_var     = optional(string)
    settings          = optional(map(string), {})
    secret_env_vars   = optional(map(string), {})
    migration_command = optional(list(string))
    run_as_non_root   = optional(bool, false)
  })
}

variable "namespace" {
  description = "Namespace de las cargas."
  type        = string
  default     = "staging"
}

variable "image_registry" {
  description = "Registro de imágenes; vacío para imágenes cargadas con kind load."
  type        = string
  default     = ""
}

variable "secret_store_name" {
  description = "Nombre del ClusterSecretStore."
  type        = string
  default     = "solventa"
}

variable "db_secret_name" {
  description = "Nombre del secreto con las credenciales de BD del servicio (username, password, host, port, dbname)."
  type        = string
}

variable "db_sslmode" {
  description = "sslmode de la URL de BD; \"disable\" omite el parámetro (kind)."
  type        = string
  default     = "require"
}

variable "cache" {
  description = "Caché: scheme (rediss|redis), host y puerto; secret_ref null si no hay token (kind)."
  type = object({
    scheme     = string
    host       = string
    port       = optional(number, 6379)
    secret_ref = optional(string)
  })
}

variable "migration_wait_timeout" {
  description = "Tiempo máximo de espera de la migración."
  type        = string
  default     = "10m"
}
