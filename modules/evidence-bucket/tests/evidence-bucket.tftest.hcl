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
    condition     = one(aws_eks_pod_identity_association.writer).service_account == "solventa-identidad" && one(aws_eks_pod_identity_association.writer).namespace == "staging"
    error_message = "Only the identidad service account in the staging namespace may assume the role."
  }

  assert {
    condition     = jsondecode(one(aws_iam_role.writer).assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
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

# HU20: documentos de póliza en un segundo bucket, sin expirar los objetos y con permiso en un rol que ya existe.
run "policy_documents_do_not_expire_and_keep_old_versions_longer" {
  command = plan

  variables {
    bucket_name     = "solventa-staging-polizas-123456789012"
    prefix          = "polizas/"
    retention_days  = null
    noncurrent_days = 30
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration) == 0
    error_message = "With retention_days = null the current objects must not expire."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "Old versions must be kept for noncurrent_days."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must stay enabled without expiration."
  }
}

run "existing_role_gets_the_policy_without_a_new_role_or_association" {
  command = plan

  variables {
    bucket_name        = "solventa-staging-polizas-123456789012"
    prefix             = "polizas/"
    existing_role_name = "solventa-staging-solventa-suscripcion-eventos"
    policy_name        = "write-polizas"
  }

  assert {
    condition     = length(aws_iam_role.writer) == 0 && length(aws_eks_pod_identity_association.writer) == 0
    error_message = "With existing_role_name no role or Pod Identity association may be created (EKS allows one association per service account)."
  }

  assert {
    condition     = aws_iam_role_policy.writer.role == "solventa-staging-solventa-suscripcion-eventos" && aws_iam_role_policy.writer.name == "write-polizas"
    error_message = "The write policy must be attached to the existing role."
  }

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.writer.policy).Statement).Action == ["s3:PutObject"] && endswith(one(jsondecode(aws_iam_role_policy.writer.policy).Statement).Resource, "/polizas/*")
    error_message = "RULE least-privilege: the existing role may only PutObject under polizas/."
  }

  assert {
    condition     = output.writer_role_arn == null
    error_message = "writer_role_arn must be null when no role is created."
  }
}

# HU21: las pólizas firmadas se guardan en firmadas/ y el servicio relee los PDF para comprobar su hash y entregarlos.
run "signed_policies_add_a_write_prefix_and_read_access_limited_to_the_same_prefixes" {
  command = plan

  variables {
    bucket_name          = "solventa-staging-polizas-123456789012"
    prefix               = "polizas/"
    extra_write_prefixes = ["firmadas/"]
    read_access          = true
    existing_role_name   = "solventa-staging-solventa-suscripcion-eventos"
    policy_name          = "documentos-polizas"
  }

  assert {
    condition     = toset(flatten([for st in jsondecode(aws_iam_role_policy.writer.policy).Statement : [for a in tolist(st.Action) : a]])) == toset(["s3:PutObject", "s3:GetObject"])
    error_message = "RULE least-privilege: the role may only PutObject and GetObject (no delete, no list, no wildcard)."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(aws_iam_role_policy.writer.policy).Statement :
      alltrue([for r in flatten([st.Resource]) : endswith(r, "/polizas/*") || endswith(r, "/firmadas/*")])
    ])
    error_message = "RULE least-privilege: every statement must be limited to polizas/ or firmadas/."
  }

  assert {
    condition = toset(flatten([
      for st in jsondecode(aws_iam_role_policy.writer.policy).Statement :
      [for r in flatten([st.Resource]) : r if contains(tolist(st.Action), "s3:GetObject")]
    ])) == toset(["arn:aws:s3:::solventa-staging-polizas-123456789012/polizas/*", "arn:aws:s3:::solventa-staging-polizas-123456789012/firmadas/*"])
    error_message = "Reads must cover exactly the write prefixes."
  }

  assert {
    condition = toset(flatten([
      for st in jsondecode(aws_iam_role_policy.writer.policy).Statement :
      [for r in flatten([st.Resource]) : r if contains(tolist(st.Action), "s3:PutObject")]
    ])) == toset(["arn:aws:s3:::solventa-staging-polizas-123456789012/polizas/*", "arn:aws:s3:::solventa-staging-polizas-123456789012/firmadas/*"])
    error_message = "Writes must cover exactly polizas/ and firmadas/."
  }
}

run "kyc_bucket_stays_write_only_without_read_access" {
  command = plan

  assert {
    condition     = !can(regex("GetObject", aws_iam_role_policy.writer.policy))
    error_message = "RULE least-privilege: the KYC role must never read evidence (read_access defaults to false)."
  }
}

run "extra_write_prefix_cannot_be_the_whole_bucket" {
  command = plan

  variables {
    extra_write_prefixes = ["/"]
  }

  expect_failures = [var.extra_write_prefixes]
}

run "extra_write_prefix_must_be_a_folder" {
  command = plan

  variables {
    extra_write_prefixes = ["firmadas"]
  }

  expect_failures = [var.extra_write_prefixes]
}

run "retention_days_must_be_null_or_positive" {
  command = plan

  variables {
    retention_days = 0
  }

  expect_failures = [var.retention_days]
}

run "listing_is_opt_in_and_limited_to_the_bucket_itself" {
  command = plan

  variables {
    bucket_name          = "solventa-staging-polizas-123456789012"
    prefix               = "polizas/"
    extra_write_prefixes = ["certificados/"]
    read_access          = true
    list_access          = true
    existing_role_name   = "solventa-staging-solventa-suscripcion-eventos"
    policy_name          = "documentos-polizas"
  }

  # Sin ListBucket, leer una clave inexistente da 403 y el servicio no distingue «no hay copia» de «sin permiso».
  assert {
    condition = toset(flatten([
      for st in jsondecode(aws_iam_role_policy.writer.policy).Statement :
      [for r in flatten([st.Resource]) : r if contains(tolist(st.Action), "s3:ListBucket")]
    ])) == toset(["arn:aws:s3:::solventa-staging-polizas-123456789012"])
    error_message = "RULE least-privilege: listing must be granted on this bucket only, never a wildcard or object path."
  }

  assert {
    condition     = toset(flatten([for st in jsondecode(aws_iam_role_policy.writer.policy).Statement : [for a in tolist(st.Action) : a]])) == toset(["s3:PutObject", "s3:GetObject", "s3:ListBucket"])
    error_message = "RULE least-privilege: with list_access the role may only Put, Get and List (no delete, no wildcard)."
  }
}

run "listing_is_never_granted_by_default" {
  command = plan

  assert {
    condition     = !can(regex("ListBucket", aws_iam_role_policy.writer.policy))
    error_message = "RULE least-privilege: list_access defaults to false, so the KYC role never lists."
  }
}
