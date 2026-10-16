resource "random_password" "auth_token" {
  length  = 32
  special = false # solo [A-Za-z0-9]: nunca requiere codificación en URL (contrato C2)
}

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "ElastiCache: acceso solo desde los nodos EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis desde nodos EKS"

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.name
  description          = "Cache de Solventa (staging)"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = var.engine == "valkey" ? "default.valkey7" : "default.redis7"

  num_cache_clusters          = 1 + var.replicas
  preferred_cache_cluster_azs = slice(var.azs, 0, min(1 + var.replicas, length(var.azs)))
  automatic_failover_enabled  = true
  multi_az_enabled            = true

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  apply_immediately = true

  tags = var.tags
}
