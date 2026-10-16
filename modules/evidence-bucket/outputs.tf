output "bucket_name" {
  description = "Nombre del bucket de evidencias (solo referencia)."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN del bucket de evidencias."
  value       = aws_s3_bucket.this.arn
}

output "writer_role_arn" {
  description = "Rol que asume el servicio para escribir evidencias."
  value       = aws_iam_role.writer.arn
}
