# T013: el bucket de estado es seguro y los roles de pipeline están limitados por repositorio.

mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

override_data {
  target = module.ci_identities.data.aws_caller_identity.current
  values = { account_id = "123456789012" }
}

override_data {
  target = module.ci_identities.data.aws_region.current
  values = { region = "us-east-1" }
}

run "state_bucket_is_hardened" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "RULE state-bucket: versioning must be enabled."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "RULE state-bucket: server-side encryption must be enabled."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "RULE state-bucket: Block Public Access must be fully enabled."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state_tls_only.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "RULE state-bucket: the bucket policy must deny non-TLS requests."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "RULE state-bucket: force_destroy must be false."
  }
}

run "pipeline_roles_cover_each_service" {
  command = plan

  assert {
    condition     = contains(keys(output.service_deploy_role_arns), "solventa-backend")
    error_message = "RULE deploy-role-per-service: the backend must get its own deploy role."
  }

  assert {
    condition     = output.state_bucket == "solventa-tfstate-123456789012-us-east-1"
    error_message = "The state bucket name must follow solventa-tfstate-<account>-<region>."
  }
}
