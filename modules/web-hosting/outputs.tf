output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "regional_domain_name" {
  description = "Dominio regional del bucket: el origen de CloudFront."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
