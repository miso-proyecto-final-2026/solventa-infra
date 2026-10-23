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

run "descriptions_use_the_character_set_aws_accepts" {
  command = plan

  # EC2 rechaza las tildes en la descripción de una regla de grupo de seguridad (InvalidParameterValue).
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.to_nodeports : can(regex("^[a-zA-Z0-9._:/()#,@\\[\\]+=&;{}!$* -]+$", r.description))])
    error_message = "RULE aws-charset: security group rule descriptions may only use a-zA-Z0-9 and ._-:/()#,@[]+=&;{}!$* (no accents)."
  }
}

run "vpc_link_only_reaches_node_ports_inside_the_vpc" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.to_nodeports : r.cidr_ipv4 == "10.40.0.0/16"])
    error_message = "RULE vpc-link-egress: the VPC Link may only talk to the VPC CIDR."
  }
}

run "only_high_volume_services_get_their_own_throttling" {
  command = plan

  variables {
    services = {
      "solventa-backend" = {
        listener_arn  = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/net/n/1/a"
        node_port     = 30080
        path_prefixes = ["/v1/cotizaciones"]
      }
      "solventa-siniestros" = {
        listener_arn  = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/net/n/1/c"
        node_port     = 30082
        path_prefixes = ["/v1/siniestros"]
        high_volume   = true
      }
    }
  }

  # El conjunto de route_settings del stage no se conoce hasta el apply: se verifica la lista que lo alimenta.
  assert {
    condition     = local.high_volume_routes == toset(["ANY /v1/siniestros", "ANY /v1/siniestros/{proxy+}"])
    error_message = "RULE high-volume: only the routes of services with high_volume get their own throttling (exact and {proxy+})."
  }

  assert {
    condition     = var.high_volume_throttling_rate_limit == 2000 && var.high_volume_throttling_burst_limit == 4000
    error_message = "RULE high-volume: the default high-volume throttling is 2000 rps / 4000 burst."
  }

  assert {
    condition     = aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 200
    error_message = "RULE throttling: the rest of the routes keep the general limit."
  }
}

run "without_high_volume_services_there_are_no_route_overrides" {
  command = plan

  assert {
    condition     = length(local.high_volume_routes) == 0
    error_message = "RULE high-volume: no service marked high_volume means no per-route override."
  }
}
