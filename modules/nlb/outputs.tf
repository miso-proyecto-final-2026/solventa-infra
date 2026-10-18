output "arn" {
  value = aws_lb.this.arn
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "listener_arns" {
  description = "ARN del listener de cada servicio (destino de las integraciones del API Gateway)."
  value       = { for name, l in aws_lb_listener.this : name => l.arn }
}
