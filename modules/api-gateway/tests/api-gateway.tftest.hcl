# El API Gateway enruta por prefijo hacia el NLB mediante un VPC Link y aplica throttling.

mock_provider "aws" {}

variables {
  name       = "solventa-staging"
  vpc_id     = "vpc-0123456789abcdef0"
  vpc_cidr   = "10.40.0.0/16"
  subnet_ids = ["subnet-a", "subnet-b"]
  services = {
    "solventa-backend" = {
      listener_arn  = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/net/n/1/a"
      node_port     = 30080
      path_prefixes = ["/v1/cotizaciones"]
    }
    "solventa-identidad" = {
      listener_arn  = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/net/n/1/b"
      node_port     = 30081
      path_prefixes = ["/v1/clientes"]
    }
  }
  tags = { Project = "solventa" }
}

run "http_api_with_vpc_link_integrations" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "RULE http-api: the gateway must be an HTTP API."
  }

  assert {
    condition     = alltrue([for i in aws_apigatewayv2_integration.this : i.connection_type == "VPC_LINK" && i.integration_type == "HTTP_PROXY"])
    error_message = "RULE vpc-link: every integration must reach the NLB through the VPC Link."
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.this) == 2
    error_message = "RULE per-service: one integration per exposed service."
  }
}

run "each_prefix_has_exact_and_proxy_routes" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 4
    error_message = "RULE routes: each prefix needs the exact route and the {proxy+} route (2 services x 2)."
  }

  assert {
    condition = alltrue([
      for k in ["ANY /v1/cotizaciones", "ANY /v1/cotizaciones/{proxy+}", "ANY /v1/clientes", "ANY /v1/clientes/{proxy+}"] :
      contains([for r in aws_apigatewayv2_route.this : r.route_key], k)
    ])
    error_message = "RULE routes: the public paths must match the prefixes declared in services.yaml."
  }
}

run "throttling_is_enabled" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 200 && aws_apigatewayv2_stage.default.default_route_settings[0].throttling_burst_limit == 400
    error_message = "RULE throttling: the default stage must throttle requests."
  }
}

run "vpc_link_only_reaches_node_ports_inside_the_vpc" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.to_nodeports : r.cidr_ipv4 == "10.40.0.0/16"])
    error_message = "RULE vpc-link-egress: the VPC Link may only talk to the VPC CIDR."
  }
}
