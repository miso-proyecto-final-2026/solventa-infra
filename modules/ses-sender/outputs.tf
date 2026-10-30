output "identity_arn" {
  description = "ARN de la identidad de SES, el único recurso sobre el que el servicio puede enviar."
  value       = local.identity_arn
}

output "sender_email" {
  description = "Dirección remitente, para entregarla al servicio (CORREO_REMITENTE)."
  value       = aws_ses_email_identity.this.email
}
