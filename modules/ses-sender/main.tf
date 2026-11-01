# Remitente de correo del servicio de notificaciones (HU22): una identidad de Amazon SES y el permiso mínimo para enviar
# con ella. SES crea la identidad pendiente y AWS manda un correo de verificación a la dirección: alguien debe abrir el
# enlace. Mientras la cuenta esté en sandbox, SES solo envía a destinatarios que también estén verificados.
#
# El permiso se adjunta al rol que el servicio ya asume (EKS admite una sola asociación de Pod Identity por cuenta de
# servicio), como en el bucket de pólizas (HU20).

locals {
  # Derivado de la región, la cuenta y la dirección (conocidos en el plan) para poder comprobar la política sin aplicar.
  identity_arn = "arn:aws:ses:${var.region}:${var.account_id}:identity/${var.sender_email}"

  # En sandbox, SES autoriza el envío contra la identidad del remitente Y la de cada destinatario: con solo la primera,
  # el envío responde AccessDenied. Se permiten las identidades de esta cuenta (nunca "*"), pero el remitente queda fijo
  # con la condición ses:FromAddress, de modo que el rol no puede enviar en nombre de otra dirección.
  identities_arn = "arn:aws:ses:${var.region}:${var.account_id}:identity/*"
}

resource "aws_ses_email_identity" "this" {
  email = var.sender_email
}

resource "aws_iam_role_policy" "send" {
  name = var.policy_name
  role = var.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail"]
      Resource = local.identities_arn
      Condition = {
        StringEquals = { "ses:FromAddress" = var.sender_email }
      }
    }]
  })
}
