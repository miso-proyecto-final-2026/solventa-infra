# Logs de Loki en S3: privado, cifrado, solo TLS, con retención de respaldo y acceso mínimo para Loki.

mock_provider "aws" {}

variables {
  bucket_name  = "solventa-staging-logs-123456789012"
  cluster_name = "solventa-staging"
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "bucket_is_private_encrypted_and_tls_only" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "RULE no-public: every public access block setting must be true."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "RULE encryption: logs must be encrypted at rest."
  }

  assert {
    condition     = one(jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement).Effect == "Deny" && one(jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "RULE tls-only: the bucket policy must deny non-TLS requests."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled (BucketOwnerEnforced)."
  }
}

run "objects_expire_as_a_safety_net" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration[0].days == 14
    error_message = "RULE logs-retention: S3 deletes logs after 14 days even if Loki's compactor fails."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 1
    error_message = "Incomplete multipart uploads must be cleaned up."
  }
}

run "loki_gets_least_privilege_on_this_bucket_only" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.loki.policy).Statement :
      alltrue([for r in flatten([s.Resource]) : startswith(r, "arn:aws:s3:::solventa-staging-logs-123456789012")])
    ])
    error_message = "RULE least-privilege: Loki's policy is limited to the logs bucket."
  }

  assert {
    condition     = !contains(flatten([for s in jsondecode(aws_iam_role_policy.loki.policy).Statement : s.Action]), "s3:*")
    error_message = "RULE least-privilege: no wildcard S3 actions."
  }

  assert {
    condition     = jsondecode(aws_iam_role.loki.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "RULE pod-identity: the role is assumed through EKS Pod Identity, not IRSA or keys."
  }

  assert {
    condition     = aws_eks_pod_identity_association.loki.namespace == "monitoring" && aws_eks_pod_identity_association.loki.service_account == "loki"
    error_message = "The association must target Loki's service account in the monitoring namespace."
  }
}

run "retention_below_two_days_is_rejected" {
  command = plan

  variables {
    retention_days = 1
  }

  expect_failures = [var.retention_days]
}
