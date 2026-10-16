variable "region" {
  description = "Región AWS."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket S3 con el estado de la etapa platform (salida state_bucket del bootstrap)."
  type        = string
}

variable "platform_state_key" {
  description = "Clave del estado de la etapa platform."
  type        = string
  default     = "staging/platform.tfstate"
}

variable "image_tags" {
  description = "Sustituye image_tag de services.yaml por servicio, p. ej. { solventa-backend = \"<sha>\" }. Debe coincidir con el SHA en ejecución (README)."
  type        = map(string)
  default     = {}
}

variable "check_images_exist" {
  description = "Verificar en ECR que cada image_tag existe antes de tocar las cargas."
  type        = bool
  default     = true
}

variable "metrics_server_args" {
  description = "Argumentos extra de metrics-server."
  type        = list(string)
  default     = []
}
