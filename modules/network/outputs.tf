output "vpc_id" {
  description = "ID de la VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR de la VPC."
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Subredes privadas (nodos, RDS, ElastiCache)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Subredes públicas (NAT, futuros balanceadores)."
  value       = module.vpc.public_subnets
}

output "azs" {
  description = "Zonas de disponibilidad usadas."
  value       = local.azs
}
