variable "region" {
  description = "Región simulada."
  type        = string
  default     = "us-east-1"
}

variable "moto_endpoint" {
  description = "URL del servidor Moto (docker run -p 5000:5000 motoserver/moto)."
  type        = string
  default     = "http://localhost:5000"
}

variable "enable_network" {
  description = "Aplicar el módulo de red (VPC, NAT, endpoint S3). Desactivar si la versión de Moto no cubre algún recurso."
  type        = bool
  default     = true
}

variable "enable_ci_identities" {
  description = "Aplicar los roles de CI y el bucket de estado del bootstrap."
  type        = bool
  default     = true
}
