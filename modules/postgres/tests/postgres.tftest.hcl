# T018: base de datos privada, cifrada, Multi-AZ, con TLS forzado y acceso solo desde nodos.

mock_provider "aws" {}

variables {
  vpc_id                    = "vpc-0123456789abcdef0"
  subnet_ids                = ["subnet-0aaa", "subnet-0bbb"]
  allowed_security_group_id = "sg-0123456789abcdef0"
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "database_is_private_encrypted_and_multi_az" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "RULE db-private: publicly_accessible must be false (FR-007)."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "RULE db-encrypted: storage_encrypted must be true (FR-012)."
  }

  assert {
    condition     = aws_db_instance.this.multi_az == true
    error_message = "RULE db-multi-az: multi_az must be honoured (true by default, FR-012)."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "RULE db-master-secret: the master password must be managed by RDS (FR-019)."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 7
    error_message = "RULE db-backups: retention must be at least 7 days (FR-012)."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.this.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "RULE db-tls: rds.force_ssl must be 1."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_nodes.referenced_security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.from_nodes.from_port == 5432
    error_message = "RULE db-network: ingress must come only from the node security group on 5432."
  }

  assert {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(aws_db_instance.this.tags), k)])
    error_message = "RULE tags: every resource must carry the five mandatory tags."
  }
}

run "multi_az_can_be_disabled_by_input" {
  command = plan

  variables {
    multi_az = false
  }

  assert {
    condition     = aws_db_instance.this.multi_az == false
    error_message = "multi_az input must be honoured."
  }
}

run "short_backup_retention_is_rejected" {
  command = plan

  variables {
    backup_retention_days = 1
  }

  expect_failures = [var.backup_retention_days]
}
