variable "name" {
  description = "Prefijo de los recursos (p. ej. solventa-staging)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC: el VPC Link solo habla hacia dentro de ella."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas donde el VPC Link crea sus interfaces (una por AZ)."
  type        = list(string)
}

variable "services" {
  description = "Servicios expuestos: nombre => listener del NLB y prefijos de ruta públicos."
  type = map(object({
    listener_arn  = string
    node_port     = number
    path_prefixes = list(string)
    high_volume   = optional(bool, false)
  }))
}

variable "throttling_rate_limit" {
  description = "Solicitudes por segundo sostenidas que admite el API Gateway (throttling)."
  type        = number
  default     = 200
}

variable "throttling_burst_limit" {
  description = "Ráfaga máxima de solicitudes simultáneas."
  type        = number
  default     = 400
}

variable "high_volume_throttling_rate_limit" {
  description = "Solicitudes por segundo sostenidas por ruta de los servicios `high_volume` (proveedores de eventos)."
  type        = number
  default     = 2000
}

variable "high_volume_throttling_burst_limit" {
  description = "Ráfaga máxima por ruta de los servicios `high_volume`."
  type        = number
  default     = 4000
}

variable "tags" {
  type    = map(string)
  default = {}
}
