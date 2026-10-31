# HU22: el servicio de notificaciones solo puede enviar con su propia identidad de SES.

mock_provider "aws" {}

variables {
  sender_email = "notificaciones@solventa.example"
  role_name    = "solventa-staging-solventa-notificaciones-eventos"
  region       = "us-east-1"
  account_id   = "123456789012"
}

run "policy_allows_only_send_email_from_the_sender_address" {
  command = plan

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.send.policy).Statement).Effect == "Allow" && one(jsondecode(aws_iam_role_policy.send.policy).Statement).Action == ["ses:SendEmail"]
    error_message = "RULE least-privilege: the role may only ses:SendEmail."
  }

  # En sandbox SES también autoriza la identidad del destinatario: se permiten las identidades de la cuenta, no "*".
  assert {
    condition     = one(jsondecode(aws_iam_role_policy.send.policy).Statement).Resource == "arn:aws:ses:us-east-1:123456789012:identity/*"
    error_message = "RULE least-privilege: sending must be limited to the SES identities of this account, never a bare wildcard."
  }

  assert {
    condition     = one(jsondecode(aws_iam_role_policy.send.policy).Statement).Condition.StringEquals["ses:FromAddress"] == "notificaciones@solventa.example"
    error_message = "RULE least-privilege: the From address must be pinned to the sender."
  }
}

run "policy_is_attached_to_the_existing_role_without_a_new_role" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.send.role == "solventa-staging-solventa-notificaciones-eventos" && aws_iam_role_policy.send.name == "enviar-correo"
    error_message = "The SES policy must be attached to the service role (EKS allows one Pod Identity association per service account)."
  }
}

run "identity_is_created_for_the_sender" {
  command = plan

  assert {
    condition     = aws_ses_email_identity.this.email == "notificaciones@solventa.example"
    error_message = "The SES identity must be the sender address."
  }

  assert {
    condition     = output.identity_arn == "arn:aws:ses:us-east-1:123456789012:identity/notificaciones@solventa.example" && output.sender_email == "notificaciones@solventa.example"
    error_message = "The outputs must expose the identity ARN and the sender."
  }
}

run "sender_must_be_an_email_address" {
  command = plan

  variables {
    sender_email = "no-es-un-correo"
  }

  expect_failures = [var.sender_email]
}
