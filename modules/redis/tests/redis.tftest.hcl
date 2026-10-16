# T019: caché cifrada en tránsito y en reposo, con failover y acceso solo desde nodos.

mock_provider "aws" {}
mock_provider "random" {}

override_resource {
  target          = random_password.auth_token
  override_during = plan
  values          = { result = "AbCdEfGhIjKlMnOpQrStUvWxYz012345" }
}

variables {
  vpc_id                    = "vpc-0123456789abcdef0"
  subnet_ids                = ["subnet-0aaa", "subnet-0bbb"]
  azs                       = ["us-east-1a", "us-east-1b"]
  allowed_security_group_id = "sg-0123456789abcdef0"
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "cache_is_encrypted_with_failover" {
  command = plan

  assert {
    condition     = tobool(aws_elasticache_replication_group.this.transit_encryption_enabled) && tobool(aws_elasticache_replication_group.this.at_rest_encryption_enabled)
    error_message = "RULE cache-encrypted: in-transit and at-rest encryption must be enabled (FR-018)."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled == true && aws_elasticache_replication_group.this.multi_az_enabled == true
    error_message = "RULE cache-failover: automatic failover and multi-AZ must be enabled (FR-018)."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters >= 2
    error_message = "RULE cache-replica: at least one replica is required."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.auth_token != null
    error_message = "RULE cache-auth: an auth token must be configured."
  }

  assert {
    condition     = random_password.auth_token.special == false && random_password.auth_token.length == 32
    error_message = "The auth token must be 32 alphanumeric characters."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_nodes.referenced_security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.from_nodes.from_port == 6379
    error_message = "RULE cache-network: ingress must come only from the node security group on 6379."
  }

  assert {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(aws_elasticache_replication_group.this.tags), k)])
    error_message = "RULE tags: every resource must carry the five mandatory tags."
  }
}

run "valkey_engine_is_accepted" {
  command = plan

  variables {
    engine = "valkey"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.engine == "valkey"
    error_message = "valkey must be selectable."
  }
}

run "zero_replicas_are_rejected" {
  command = plan

  variables {
    replicas = 0
  }

  expect_failures = [var.replicas]
}
