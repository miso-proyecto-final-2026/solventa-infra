# Bus de eventos de Solventa (ADR-0002). Privado, cifrado, solo SASL/IAM y permisos mínimos por servicio.

locals {
  # Los ARN de topics y grupos se derivan del ARN del clúster: cluster/<nombre>/<uuid> -> topic/<nombre>/<uuid>/<topic>.
  topic_arn_prefix = replace(aws_msk_cluster.this.arn, ":cluster/", ":topic/")
  group_arn_prefix = replace(aws_msk_cluster.this.arn, ":cluster/", ":group/")

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# ---------------------------------------------------------------------------
# Red: solo los nodos de EKS llegan a los brokers, por el puerto de SASL/IAM
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "MSK: acceso solo desde los nodos EKS"
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
  from_port                    = 9098
  to_port                      = 9098
  description                  = "Kafka SASL/IAM sobre TLS desde nodos EKS"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Configuración y clúster
# ---------------------------------------------------------------------------
resource "aws_msk_configuration" "this" {
  name           = "${var.name}-config"
  kafka_versions = [var.kafka_version]
  description    = "Solventa: los topics solo existen si se declaran; replicación 2 con dos brokers."

  server_properties = <<-EOT
    auto.create.topics.enable=false
    default.replication.factor=2
    min.insync.replicas=1
    offsets.topic.replication.factor=2
    transaction.state.log.replication.factor=2
    transaction.state.log.min.isr=1
    delete.topic.enable=true
  EOT
}

# Logs de los brokers (CKV_AWS_80): evidencia de auditoría de las conexiones y de los errores de autorización.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/msk/${var.name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_group_info {
    instance_type   = var.broker_node_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.this.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size_gb
      }
    }

    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = false

    sasl {
      iam = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.this.name
      }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Acceso por servicio: Pod Identity, solo sus topics y sus grupos de consumo
# ---------------------------------------------------------------------------
resource "aws_iam_role" "client" {
  for_each = var.access

  name               = "${var.cluster_name}-${each.key}-eventos"
  assume_role_policy = local.assume_role_policy

  tags = var.tags
}

resource "aws_iam_role_policy" "client" {
  for_each = var.access

  name = "eventos-minimos"
  role = aws_iam_role.client[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "Conectar"
        Effect   = "Allow"
        Action   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource = [aws_msk_cluster.this.arn]
      }],
      # Las sentencias opcionales se construyen con `for ... if` para que todas tengan la misma forma.
      # El cliente publica con `enable_idempotence`: pide un ID de productor, que MSK autoriza sobre el clúster y no sobre un topic.
      # Sin este permiso el productor falla al arrancar con ClusterAuthorizationFailedError. También lo usa quien escribe en la cola de fallidos.
      [for _ in range(length(each.value.produce) + length(each.value.consume) > 0 ? 1 : 0) : {
        Sid      = "ProductorIdempotente"
        Effect   = "Allow"
        Action   = ["kafka-cluster:WriteDataIdempotently"]
        Resource = [aws_msk_cluster.this.arn]
      }],
      [for _ in range(length(each.value.produce) > 0 ? 1 : 0) : {
        Sid      = "Publicar"
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
        Resource = [for t in each.value.produce : "${local.topic_arn_prefix}/${t}"]
      }],
      [for _ in range(length(each.value.consume) > 0 ? 1 : 0) : {
        Sid      = "Consumir"
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
        Resource = [for t in each.value.consume : "${local.topic_arn_prefix}/${t}"]
      }],
      [for _ in range(length(each.value.consume) > 0 ? 1 : 0) : {
        Sid      = "ColaDeFallidos"
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
        Resource = [for t in each.value.consume : "${local.topic_arn_prefix}/${t}.dlq"]
      }],
      [for _ in range(length(each.value.consume) > 0 ? 1 : 0) : {
        Sid      = "GrupoDeConsumo"
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = ["${local.group_arn_prefix}/${each.key}*"]
      }],
    )
  })
}

resource "aws_eks_pod_identity_association" "client" {
  for_each = var.access

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.client[each.key].arn

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Administrador de topics: crea y ajusta topics, nunca lee ni escribe eventos
# ---------------------------------------------------------------------------
resource "aws_iam_role" "admin" {
  name               = "${var.cluster_name}-${var.admin_service_account}-eventos"
  assume_role_policy = local.assume_role_policy

  tags = var.tags
}

resource "aws_iam_role_policy" "admin" {
  name = "administrar-topics"
  role = aws_iam_role.admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Conectar"
        Effect   = "Allow"
        Action   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource = [aws_msk_cluster.this.arn]
      },
      {
        Sid    = "AdministrarTopics"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration",
        ]
        Resource = ["${local.topic_arn_prefix}/*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "admin" {
  cluster_name    = var.cluster_name
  namespace       = var.admin_namespace
  service_account = var.admin_service_account
  role_arn        = aws_iam_role.admin.arn

  tags = var.tags
}
