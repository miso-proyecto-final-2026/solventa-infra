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

variable "tags" {
  type    = map(string)
  default = {}
}
