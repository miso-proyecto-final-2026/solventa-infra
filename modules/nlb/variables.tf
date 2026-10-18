variable "name" {
  description = "Prefijo de los recursos (p. ej. solventa-staging)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC: origen permitido hacia los NodePort (el tráfico llega desde el VPC Link y el NLB)."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas (una por AZ): el NLB es interno y multi-AZ."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "El NLB necesita al menos 2 subredes en AZ distintas (disponibilidad multi-AZ)."
  }
}

variable "node_security_group_id" {
  description = "Grupo de seguridad de los nodos, donde se abre el NodePort de cada servicio."
  type        = string
}

variable "autoscaling_group_names" {
  description = "Grupos de autoescalado cuyos nodos reciben el tráfico: nombre del node group (estático) => nombre del ASG."
  type        = map(string)
}

variable "services" {
  description = "Servicios expuestos: nombre => NodePort (el listener usa el mismo puerto)."
  type        = map(object({ node_port = number }))
}

variable "tags" {
  type    = map(string)
  default = {}
}
