# HS2: bus de eventos privado, cifrado, con autenticación IAM y permisos mínimos por servicio.

mock_provider "aws" {}

# Con el ARN conocido en el plan, las políticas de IAM se pueden inspeccionar.
override_resource {
  target          = aws_msk_cluster.this
  override_during = plan
  values = {
    arn = "arn:aws:kafka:us-east-1:123456789012:cluster/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1"
  }
}

variables {
  cluster_name              = "solventa-staging"
  vpc_id                    = "vpc-0123456789abcdef0"
  subnet_ids                = ["subnet-0aaa", "subnet-0bbb"]
  allowed_security_group_id = "sg-0123456789abcdef0"

  access = {
    "svc-a" = {
      namespace       = "staging"
      service_account = "svc-a"
      produce         = ["solventa.a.comandos"]
      consume         = ["solventa.b.resultados"]
    }
    "svc-b" = {
      namespace       = "staging"
      service_account = "svc-b"
      produce         = ["solventa.b.resultados"]
      consume         = []
    }
  }

  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "cluster_is_private_encrypted_and_iam_only" {
  command = plan

  assert {
    condition     = aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].client_broker == "TLS" && aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].in_cluster == true
    error_message = "RULE msk-tls: clients and brokers must talk over TLS, also inside the cluster."
  }

  assert {
    condition     = aws_msk_cluster.this.client_authentication[0].sasl[0].iam == true && aws_msk_cluster.this.client_authentication[0].unauthenticated == false
    error_message = "RULE msk-auth: only SASL/IAM, no unauthenticated access."
  }

  assert {
    condition     = aws_msk_cluster.this.broker_node_group_info[0].connectivity_info[0].public_access[0].type == "DISABLED"
    error_message = "RULE msk-private: the cluster must have no public access."
  }
}

run "broker_logs_are_kept_for_audit" {
  command = plan

  assert {
    condition     = aws_msk_cluster.this.logging_info[0].broker_logs[0].cloudwatch_logs[0].enabled == true
    error_message = "RULE msk-logs: broker logs go to CloudWatch (audit evidence for HA05, CKV_AWS_80)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "Broker logs are kept 14 days by default (cost)."
  }
}

run "cluster_spans_two_zones_with_small_brokers" {
  command = plan

  assert {
    condition     = aws_msk_cluster.this.number_of_broker_nodes == 2 && length(aws_msk_cluster.this.broker_node_group_info[0].client_subnets) == 2
    error_message = "RULE msk-multi-az: one broker per zone, two zones."
  }

  assert {
    condition     = aws_msk_cluster.this.broker_node_group_info[0].instance_type == "kafka.t3.small"
    error_message = "The default broker type must be kafka.t3.small (staging cost)."
  }

  assert {
    condition     = aws_msk_cluster.this.broker_node_group_info[0].storage_info[0].ebs_storage_info[0].volume_size == 10
    error_message = "The default volume must be 10 GiB per broker."
  }
}

run "network_only_from_nodes_on_the_iam_port" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_nodes.referenced_security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.from_nodes.from_port == 9098 && aws_vpc_security_group_ingress_rule.from_nodes.to_port == 9098
    error_message = "RULE msk-network: ingress only from the node security group on 9098 (SASL/IAM over TLS)."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_nodes.cidr_ipv4 == null
    error_message = "RULE msk-network: no CIDR ingress."
  }
}

run "topics_are_never_created_by_accident" {
  command = plan

  assert {
    condition     = strcontains(aws_msk_configuration.this.server_properties, "auto.create.topics.enable=false")
    error_message = "RULE msk-topics: topics only exist if declared (auto.create.topics.enable=false)."
  }

  assert {
    condition     = strcontains(aws_msk_configuration.this.server_properties, "default.replication.factor=2") && strcontains(aws_msk_configuration.this.server_properties, "min.insync.replicas=1")
    error_message = "With two brokers, replication factor 2 and min.insync.replicas 1 keep the service alive when one broker is down."
  }
}

run "each_service_gets_a_role_with_only_its_topics" {
  command = plan

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement[0].Action, "kafka-cluster:Connect") && jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement[0].Resource[0] == "arn:aws:kafka:us-east-1:123456789012:cluster/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1"
    error_message = "RULE msk-access: the first statement is the connection to the cluster, and only to it."
  }

  assert {
    condition = contains(flatten([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      s.Resource if contains(s.Action, "kafka-cluster:WriteData")
    ]), "arn:aws:kafka:us-east-1:123456789012:topic/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1/solventa.a.comandos")
    error_message = "RULE msk-access: the producer can write to its own topic."
  }

  assert {
    condition = contains(flatten([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      s.Resource if contains(s.Action, "kafka-cluster:ReadData")
    ]), "arn:aws:kafka:us-east-1:123456789012:topic/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1/solventa.b.resultados")
    error_message = "RULE msk-access: the consumer can read the topic it consumes."
  }

  assert {
    condition = contains(flatten([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      s.Resource if contains(s.Action, "kafka-cluster:WriteData")
    ]), "arn:aws:kafka:us-east-1:123456789012:topic/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1/solventa.b.resultados.dlq")
    error_message = "RULE msk-access: a consumer can send to the dead-letter topic of what it consumes."
  }

  # El productor idempotente pide un ID de productor, que MSK autoriza sobre el clúster; sin esto el servicio no arranca.
  assert {
    condition = alltrue([
      for n in ["svc-a", "svc-b"] : contains(flatten([
        for s in jsondecode(aws_iam_role_policy.client[n].policy).Statement :
        s.Resource if contains(s.Action, "kafka-cluster:WriteDataIdempotently")
      ]), "arn:aws:kafka:us-east-1:123456789012:cluster/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1")
    ])
    error_message = "RULE msk-idempotent: every service that publishes needs WriteDataIdempotently on the cluster (and only on it)."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      alltrue([for r in flatten([s.Resource]) : !endswith(r, "/*") && r != "*"])
    ])
    error_message = "RULE msk-access: no wildcard resource (no topic of another service)."
  }

  assert {
    condition = !contains(flatten([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      s.Resource if contains(s.Action, "kafka-cluster:ReadData")
    ]), "arn:aws:kafka:us-east-1:123456789012:topic/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1/solventa.a.comandos")
    error_message = "RULE msk-access: a service must not read the topic it only produces."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_iam_role_policy.client["svc-b"].policy).Statement :
      s if contains(s.Action, "kafka-cluster:ReadData")
    ]) == 0
    error_message = "RULE msk-access: a producer-only service has no read permission."
  }
}

run "consumers_can_only_use_their_own_consumer_groups" {
  command = plan

  assert {
    condition = contains(flatten([
      for s in jsondecode(aws_iam_role_policy.client["svc-a"].policy).Statement :
      s.Resource if contains(s.Action, "kafka-cluster:AlterGroup")
    ]), "arn:aws:kafka:us-east-1:123456789012:group/solventa-staging-events/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee-1/svc-a*")
    error_message = "RULE msk-groups: consumer groups are limited to the service name prefix."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_iam_role_policy.client["svc-b"].policy).Statement :
      s if contains(s.Action, "kafka-cluster:AlterGroup")
    ]) == 0
    error_message = "A service that consumes nothing has no consumer-group permission."
  }
}

run "roles_are_bound_to_the_service_account_by_pod_identity" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.client["svc-a"].cluster_name == "solventa-staging" && aws_eks_pod_identity_association.client["svc-a"].namespace == "staging" && aws_eks_pod_identity_association.client["svc-a"].service_account == "svc-a"
    error_message = "RULE msk-identity: the role is associated to the namespace and service account of the service."
  }

  assert {
    condition     = jsondecode(aws_iam_role.client["svc-a"].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "Only EKS Pod Identity may assume the service roles."
  }
}

run "topic_admin_can_create_but_not_read_or_write_data" {
  command = plan

  assert {
    condition     = contains(flatten([for s in jsondecode(aws_iam_role_policy.admin.policy).Statement : s.Action]), "kafka-cluster:CreateTopic")
    error_message = "RULE msk-admin: the topic job must be able to create topics."
  }

  assert {
    condition     = !contains(flatten([for s in jsondecode(aws_iam_role_policy.admin.policy).Statement : s.Action]), "kafka-cluster:ReadData") && !contains(flatten([for s in jsondecode(aws_iam_role_policy.admin.policy).Statement : s.Action]), "kafka-cluster:WriteData")
    error_message = "RULE msk-admin: the admin role never touches event data."
  }

  assert {
    condition     = aws_eks_pod_identity_association.admin.namespace == "solventa-system" && aws_eks_pod_identity_association.admin.service_account == "kafka-topics"
    error_message = "The admin role belongs to the kafka-topics service account in solventa-system."
  }
}

run "broker_count_must_fit_the_zones" {
  command = plan

  variables {
    broker_count = 3
  }

  expect_failures = [var.broker_count]
}

run "topics_must_have_a_valid_name" {
  command = plan

  variables {
    access = {
      "svc-a" = {
        namespace       = "staging"
        service_account = "svc-a"
        produce         = ["*"]
        consume         = []
      }
    }
  }

  expect_failures = [var.access]
}

run "tags_are_mandatory" {
  command = plan

  variables {
    tags = { Project = "solventa" }
  }

  expect_failures = [var.tags]
}

run "small_brokers_cannot_use_kraft" {
  command = plan

  variables {
    broker_node_type = "kafka.t3.small"
    kafka_version    = "3.9.x.kraft"
  }

  expect_failures = [var.kafka_version]
}

run "kraft_is_fine_with_bigger_brokers" {
  command = plan

  variables {
    broker_node_type = "kafka.m7g.large"
    kafka_version    = "3.9.x.kraft"
  }

  assert {
    condition     = aws_msk_cluster.this.kafka_version == "3.9.x.kraft"
    error_message = "KRaft is allowed on m5/m7g brokers."
  }
}

run "default_version_works_with_the_default_broker" {
  command = plan

  assert {
    condition     = !endswith(aws_msk_cluster.this.kafka_version, ".kraft") && aws_msk_cluster.this.broker_node_group_info[0].instance_type == "kafka.t3.small"
    error_message = "The defaults (kafka.t3.small and a ZooKeeper-based version) must be a combination MSK accepts."
  }
}
