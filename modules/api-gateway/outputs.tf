output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "domain_name" {
  description = "Dominio del API Gateway (origen de CloudFront), sin esquema."
  value       = replace(aws_apigatewayv2_api.this.api_endpoint, "https://", "")
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}
