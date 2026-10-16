# Valores por defecto de staging (FR-004). Cambiar aquí, no en el código.
region   = "us-east-1"
name     = "staging"
az_count = 2

vpc_cidr               = "10.40.0.0/16"
one_nat_gateway_per_az = false

kubernetes_version = "1.35"
node_instance_type = "t3.medium"
node_count         = 3

# Restringir a la IP del equipo cuando sea posible (FR-011a).
api_allowed_cidrs = ["0.0.0.0/0"]

# Principales IAM adicionales con rol de administrador (el rol de apply de CI siempre se incluye).
cluster_admin_principal_arns = []

db_instance_class        = "db.t4g.micro"
db_multi_az              = true
db_backup_retention_days = 7
db_deletion_protection   = false
db_final_snapshot        = false

cache_node_type = "cache.t4g.micro"
cache_engine    = "redis"
cache_replicas  = 1
