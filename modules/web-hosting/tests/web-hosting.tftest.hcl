# El bucket de la consola web es privado: solo lo lee la distribución indicada y siempre por HTTPS.

mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::solventa-staging-web-123"
    }
  }
}

variables {
  bucket_name      = "solventa-staging-web-123"
  distribution_arn = "arn:aws:cloudfront::123:distribution/EABC"
}

run "bucket_is_private" {
  command = apply

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "RULE web-bucket-private: the web bucket must block all public access."
  }
}

run "only_the_distribution_reads" {
  command = apply

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect != "Allow" || (
        try(s.Principal.Service, "") == "cloudfront.amazonaws.com" &&
        s.Action == "s3:GetObject" &&
        s.Condition.StringEquals["AWS:SourceArn"] == var.distribution_arn
      )
    ])
    error_message = "RULE web-bucket-reader: only the given CloudFront distribution may read the web bucket."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && s.Condition.Bool["aws:SecureTransport"] == "false"
    ])
    error_message = "RULE web-bucket-https: the web bucket must reject requests without TLS."
  }
}
