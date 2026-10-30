variable "sender_email" {
  description = "Dirección desde la que se envía el correo. Se verifica en SES: AWS manda un enlace de confirmación a ella."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.sender_email))
    error_message = "sender_email must be a valid email address."
  }
}

variable "role_name" {
  description = "Rol de Pod Identity del servicio que envía, al que se adjunta el permiso."
  type        = string
}

variable "region" {
  description = "Región de SES."
  type        = string
}

variable "account_id" {
  description = "Cuenta de AWS dueña de la identidad."
  type        = string
}

variable "policy_name" {
  description = "Nombre de la política en línea."
  type        = string
  default     = "enviar-correo"
}
