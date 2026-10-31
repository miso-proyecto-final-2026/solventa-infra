variable "bucket_name" {
  description = "Nombre del bucket de los archivos estáticos de la consola web."
  type        = string
}

variable "distribution_arn" {
  description = "ARN de la distribución de CloudFront: la única que puede leer el bucket."
  type        = string
}

variable "tags" {
  description = "Etiquetas de los recursos."
  type        = map(string)
  default     = {}
}
