# HU02, criterio 7: evidencias cifradas, sin acceso público, solo por TLS y con escritura mínima.

mock_provider "aws" {}

variables {
  bucket_name     = "solventa-staging-kyc-evidencias-123456789012"
  cluster_name    = "solventa-staging"
  service_account = "solventa-identidad"
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
    error_message = "RULE encryption: objects must be encrypted at rest."
  }

  assert {
    condition     = one(jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement).Effect == "Deny" && one(jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "RULE tls-only: the bucket policy must deny non-TLS requests."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled (BucketOwnerEnforced)."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled to protect evidence."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "RULE no-force-destroy: force_destroy must default to false."
  }
}

run "evidence_expires_after_the_retention_period" {
  command = plan

  variables {
    retention_days = 30
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration[0].days == 30
    error_message = "Evidence must expire after retention_days."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 1
    error_message = "Incomplete multipart uploads must be aborted."
  }
}

run "service_can_only_put_objects_under_the_evidence_prefix" {
  command = plan

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.writer.policy).Statement).Action == ["s3:PutObject"]
    error_message = "RULE least-privilege: the service role may only PutObject."
  }

  assert {
    condition     = endswith(one(jsondecode(aws_iam_role_policy.writer.policy).Statement).Resource, "/kyc/*")
    error_message = "Writes must be limited to the kyc/ prefix."
  }

  assert {
    condition     = aws_eks_pod_identity_association.writer.service_account == "solventa-identidad" && aws_eks_pod_identity_association.writer.namespace == "staging"
    error_message = "Only the identidad service account in the staging namespace may assume the role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.writer.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "The role must be assumable only through EKS Pod Identity."
  }
}

run "tags_are_mandatory" {
  command = plan

  variables {
    tags = { Project = "solventa" }
  }

  expect_failures = [var.tags]
}
