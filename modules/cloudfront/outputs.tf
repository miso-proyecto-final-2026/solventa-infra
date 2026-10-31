output "domain_name" {
  description = "Dominio público de la distribución (sin esquema)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "url" {
  description = "URL base pública (la que usan la app móvil y los compañeros)."
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}
