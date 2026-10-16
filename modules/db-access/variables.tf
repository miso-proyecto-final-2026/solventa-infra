variable "services" {
  description = "Mapa nombre => { role_name, owned_schemas }."
  type = map(object({
    role_name     = string
    owned_schemas = list(string)
  }))

  # V2: cada esquema tiene como máximo un dueño.
  validation {
    condition = alltrue([
      for sc in distinct(flatten([for s in var.services : s.owned_schemas])) :
      length([for s in var.services : s if contains(s.owned_schemas, sc)]) <= 1
    ])
    error_message = "A schema is owned by more than one service (V2)."
  }
}

variable "reserved_schemas" {
  description = "Esquemas reservados sin dueño."
  type        = list(string)
  default     = []

  # V3: un esquema no puede ser reservado y tener dueño.
  validation {
    condition     = alltrue([for sc in var.reserved_schemas : length([for s in var.services : s if contains(s.owned_schemas, sc)]) == 0])
    error_message = "A schema is both reserved and owned (V3). Remove it from reserved_schemas to assign it."
  }
}

variable "drop_schemas" {
  description = "Esquemas a eliminar de forma explícita (solo si no tienen dueño)."
  type        = list(string)
  default     = []

  # V4: un esquema en drop_schemas no puede tener dueño.
  validation {
    condition     = alltrue([for sc in var.drop_schemas : length([for s in var.services : s if contains(s.owned_schemas, sc)]) == 0])
    error_message = "A schema in drop_schemas is owned by a service (V4)."
  }
}

variable "db" {
  description = "Conexión del administrador: host, referencia del secreto maestro y sslmode."
  type = object({
    host             = string
    port             = optional(number, 5432)
    name             = optional(string, "solventa")
    admin_secret_ref = string
    sslmode          = optional(string, "require")
  })
}

variable "secret_store_name" {
  description = "Nombre del ClusterSecretStore."
  type        = string
  default     = "solventa"
}

variable "service_db_secret_names" {
  description = "Mapa servicio => nombre del secreto con la contraseña del rol."
  type        = map(string)
}

variable "service_db_secret_versions" {
  description = "Mapa servicio => version_id del secreto (cambia el hash del Job al rotar contraseñas)."
  type        = map(string)
  default     = {}
}

variable "namespace" {
  description = "Namespace donde corre el Job."
  type        = string
  default     = "solventa-system"
}

variable "image" {
  description = "Imagen con el cliente psql."
  type        = string
  default     = "postgres:16-alpine"
}

variable "job_timeout" {
  description = "Tiempo máximo de espera del Job."
  type        = string
  default     = "10m"
}
