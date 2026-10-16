variable "name" {
  description = "Identificador del replication group."
  type        = string
  default     = "solventa-staging-cache"
}

variable "vpc_id" {
  description = "VPC donde vive la caché."
  type        = string
}

variable "subnet_ids" {
  description = "Subredes privadas del grupo de subredes."
  type        = list(string)
}

variable "azs" {
  description = "AZ donde se colocan los nodos (uno por AZ)."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Único security group con acceso al puerto 6379 (nodos EKS, FR-007)."
  type        = string
}

variable "node_type" {
  description = "Tipo de nodo."
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine" {
  description = "Motor: redis o valkey (FR-018)."
  type        = string
  default     = "redis"

  validation {
    condition     = contains(["redis", "valkey"], var.engine)
    error_message = "engine must be redis or valkey."
  }
}

variable "engine_version" {
  description = "Versión del motor."
  type        = string
  default     = "7.1"
}

variable "replicas" {
  description = "Réplicas por nodo primario (mínimo 1 para failover, FR-018)."
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1 (FR-018)."
  }
}

variable "tags" {
  description = "Etiquetas obligatorias (FR-005): Project, Environment, Repository, ManagedBy, Stage."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(var.tags), k)])
    error_message = "tags must include Project, Environment, Repository, ManagedBy and Stage (FR-005)."
  }
}
