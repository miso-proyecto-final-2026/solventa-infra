variable "config" {
  description = <<-EOT
    Contenido decodificado de services.yaml (contrato C1): reserved_schemas, drop_schemas y services.
    `cache_env_var: ""` desactiva el acceso a la caché (el YAML `null` no se distingue de "omitido").
  EOT

  type = object({
    reserved_schemas = optional(list(string), [])
    drop_schemas     = optional(list(string), [])
    services = list(object({
      name        = string
      image_tag   = string
      port        = number
      health_path = string
      resources = object({
        requests = object({ cpu = string, memory = string })
        limits   = object({ cpu = string, memory = string })
      })
      replicas          = object({ min = number, max = number })
      autoscaling       = optional(object({ cpu_target_percent = optional(number, 70) }), {})
      owned_schemas     = optional(list(string), [])
      database_env_vars = optional(list(string), ["DATABASE_URL"])
      cache_env_var     = optional(string, "REDIS_URL")
      settings          = optional(map(string), {})
      secret_env_vars   = optional(map(string), {})
      migration_command = optional(list(string))
      run_as_non_root   = optional(bool, false)
      deploy_repository = optional(string)
    }))
  })

  # V1: nombre válido
  validation {
    condition = alltrue([
      for s in var.config.services : can(regex("^[a-z][a-z0-9-]{2,30}$", s.name))
    ])
    error_message = format(
      "Service name \"%s\" is invalid or duplicated.",
      join("\", \"", [for s in var.config.services : s.name if !can(regex("^[a-z][a-z0-9-]{2,30}$", s.name))])
    )
  }

  # V1: nombre único
  validation {
    condition = length(distinct([for s in var.config.services : s.name])) == length(var.config.services)
    error_message = format(
      "Service name \"%s\" is invalid or duplicated.",
      join("\", \"", distinct([
        for s in var.config.services : s.name
        if length([for t in var.config.services : t.name if t.name == s.name]) > 1
      ]))
    )
  }

  # V2: cada esquema tiene como máximo un dueño
  validation {
    condition = alltrue([
      for schema in distinct(flatten([for s in var.config.services : s.owned_schemas])) :
      length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) <= 1
    ])
    error_message = format(
      "Schema \"%s\" is owned by more than one service: %s.",
      join("\", \"", [
        for schema in distinct(flatten([for s in var.config.services : s.owned_schemas])) : schema
        if length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) > 1
      ]),
      join(", ", flatten([
        for schema in distinct(flatten([for s in var.config.services : s.owned_schemas])) :
        [for s in var.config.services : s.name if contains(s.owned_schemas, schema)]
        if length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) > 1
      ]))
    )
  }

  # V3: un esquema no puede ser reservado y con dueño a la vez
  validation {
    condition = alltrue([
      for schema in var.config.reserved_schemas :
      length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) == 0
    ])
    error_message = format(
      "Schema \"%s\" is both reserved and owned by %s. Remove it from reserved_schemas to assign it.",
      join("\", \"", [
        for schema in var.config.reserved_schemas : schema
        if length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) > 0
      ]),
      join(", ", flatten([
        for schema in var.config.reserved_schemas :
        [for s in var.config.services : s.name if contains(s.owned_schemas, schema)]
      ]))
    )
  }

  # V4: un esquema en drop_schemas no puede tener dueño
  validation {
    condition = alltrue([
      for schema in var.config.drop_schemas :
      length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) == 0
    ])
    error_message = format(
      "Schema \"%s\" is listed in drop_schemas but is owned by %s.",
      join("\", \"", [
        for schema in var.config.drop_schemas : schema
        if length([for s in var.config.services : s.name if contains(s.owned_schemas, schema)]) > 0
      ]),
      join(", ", flatten([
        for schema in var.config.drop_schemas :
        [for s in var.config.services : s.name if contains(s.owned_schemas, schema)]
      ]))
    )
  }

  # V5: réplicas mínimas y máximas
  validation {
    condition = alltrue([
      for s in var.config.services : s.replicas.min >= 2 && s.replicas.max >= s.replicas.min
    ])
    error_message = format(
      "Service \"%s\": replicas.min must be ≥ 2 and ≤ replicas.max.",
      join("\", \"", [for s in var.config.services : s.name if !(s.replicas.min >= 2 && s.replicas.max >= s.replicas.min)])
    )
  }

  # V6: las claves de settings no colisionan con variables de conexión generadas
  validation {
    condition = alltrue([
      for s in var.config.services : alltrue([
        for k in keys(s.settings) :
        !contains(concat(s.database_env_vars, s.cache_env_var == "" ? [] : [s.cache_env_var]), k)
      ])
    ])
    error_message = format(
      "Service \"%s\": setting \"%s\" collides with a generated connection variable.",
      join("\", \"", [
        for s in var.config.services : s.name
        if anytrue([for k in keys(s.settings) : contains(concat(s.database_env_vars, s.cache_env_var == "" ? [] : [s.cache_env_var]), k)])
      ]),
      join("\", \"", flatten([
        for s in var.config.services : [
          for k in keys(s.settings) : k
          if contains(concat(s.database_env_vars, s.cache_env_var == "" ? [] : [s.cache_env_var]), k)
        ]
      ]))
    )
  }

  # V7: puerto y health_path
  validation {
    condition = alltrue([
      for s in var.config.services : s.port >= 1 && s.port <= 65535 && startswith(s.health_path, "/")
    ])
    error_message = format(
      "Service \"%s\": invalid port or health_path.",
      join("\", \"", [for s in var.config.services : s.name if !(s.port >= 1 && s.port <= 65535 && startswith(s.health_path, "/"))])
    )
  }

  # V8: secret_env_vars no colisiona con conexiones generadas ni con settings, y apunta a secretos del prefijo
  validation {
    condition = alltrue([
      for s in var.config.services : alltrue([
        for k, name in s.secret_env_vars :
        !contains(concat(s.database_env_vars, s.cache_env_var == "" ? [] : [s.cache_env_var], keys(s.settings)), k)
        && startswith(name, "solventa/")
      ])
    ])
    error_message = "A secret_env_vars entry collides with a connection variable or a setting, or its secret name does not start with \"solventa/\"."
  }
}
