output "bucket_name" {
  description = "Bucket donde Loki guarda chunks e índice."
  value       = aws_s3_bucket.this.bucket
}

output "role_arn" {
  description = "Rol de Pod Identity de Loki."
  value       = aws_iam_role.loki.arn
}
