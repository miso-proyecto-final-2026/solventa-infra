variable "name" {
  description = "Prefijo de nombre (solventa-<entorno>)."
  type        = string
  default     = "solventa-staging"
}

variable "cluster_name" {
  description = "Nombre del clúster EKS, para las etiquetas de subredes."
  type        = string
  default     = "solventa-staging"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (/16 a /20)."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR between /16 and /20."
  }
}

variable "az_count" {
  description = "Número de zonas de disponibilidad (mínimo 2, FR-006)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 (FR-006)."
  }
}

variable "one_nat_gateway_per_az" {
  description = "Un NAT gateway por AZ (true) o uno solo compartido (false, ahorra costo)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
