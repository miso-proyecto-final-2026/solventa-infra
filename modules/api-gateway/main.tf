# API Gateway (HTTP API): enrutamiento por prefijo hacia cada microservicio y throttling.
# Entra desde CloudFront (con WAF) y sale por un VPC Link hacia el NLB interno.
#
# La autenticación OAuth2/OIDC del documento de arquitectura no se valida aquí todavía: MS Identidad emite hoy
# un token opaco propio, no un JWT, y cada servicio lo valida. Ver README ("Borde público").

locals {
  routes = merge([
    for name, s in var.services : merge([
      for p in s.path_prefixes : {
        "${name}|ANY ${p}"          = { service = name }
        "${name}|ANY ${p}/{proxy+}" = { service = name }
      }
    ]...)
  ]...)
}

resource "aws_security_group" "vpc_link" {
  name        = "${var.name}-apigw-vpclink"
  description = "VPC Link del API Gateway hacia el NLB interno"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-apigw-vpclink" })
}

resource "aws_vpc_security_group_egress_rule" "to_nodeports" {
  for_each = var.services

  security_group_id = aws_security_group.vpc_link.id
  description       = "Hacia el NodePort de ${each.key} por el NLB"
  ip_protocol       = "tcp"
  from_port         = each.value.node_port
  to_port           = each.value.node_port
  cidr_ipv4         = var.vpc_cidr

  tags = var.tags
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.name}-nlb"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.subnet_ids

  tags = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"
  description   = "Punto unico de entrada de Solventa (borde publico)"

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = var.services

  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = each.value.listener_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  payload_format_version = "1.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = split("|", each.key)[1]
  target    = "integrations/${aws_apigatewayv2_integration.this[each.value.service].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  tags = var.tags
}
