variable "name" {
  description = "Prefijo de los recursos (p. ej. solventa-staging)."
  type        = string
}

variable "origin_domain" {
  description = "Dominio del API Gateway (origen), sin esquema."
  type        = string
}

variable "enable_web" {
  description = "Sirve también la consola web (HU39). Falso: todo va al API Gateway. Es aparte del dominio porque ese no se conoce en el plan."
  type        = bool
  default     = false
}

variable "web_origin_domain" {
  description = "Dominio regional del bucket de la consola web; obligatorio con `enable_web`."
  type        = string
  default     = null
}

variable "allowed_countries" {
  description = "Países de origen permitidos (ISO 3166-1 alfa-2); el resto se bloquea en el WAF."
  type        = list(string)
  default     = ["CO", "US"]
}

variable "rate_limit_per_5min" {
  description = "Máximo de solicitudes por IP en 5 minutos antes de responder 429."
  type        = number
  default     = 1000
}

variable "high_volume_path_regex" {
  description = <<-EOT
    Rutas (regex sobre uri_path) de los servicios `high_volume` de services.yaml: proveedores externos que envían ráfagas
    legítimas (p. ej. eventos paramétricos, EC-E2.1). Quedan fuera del límite global por IP y tienen el suyo, más alto.
    Vacío = ninguna ruta de alto volumen.
  EOT
  type        = string
  default     = ""
}

variable "high_volume_rate_limit_per_5min" {
  description = "Máximo de solicitudes por IP en 5 minutos en las rutas de alto volumen antes de responder 429."
  type        = number
  default     = 600000
}

variable "exempt_body_path_regex" {
  description = <<-EOT
    Ruta (regex sobre uri_path) exenta del límite de cuerpo y de la inspección del contenido (SQLi/XSS en body).
    Por defecto, la subida multipart de la verificación de identidad (documento y selfie, HU02), que supera 256 KB
    y es binaria: se valida en el servicio, que ya rechaza imágenes por encima de su máximo.
  EOT
  type        = string
  default     = "^/v1/clientes/[^/]+/verificaciones$"
}

variable "tags" {
  type    = map(string)
  default = {}
}
