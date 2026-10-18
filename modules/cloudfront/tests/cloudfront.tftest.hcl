# El WAF aplica las reglas del documento de arquitectura y CloudFront solo habla HTTPS con el API Gateway.

mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  name          = "solventa-staging"
  origin_domain = "abc123.execute-api.us-east-1.amazonaws.com"
  tags          = { Project = "solventa" }
}

run "waf_has_the_architecture_rules" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT"
    error_message = "RULE waf-scope: the WAF must be linked to CloudFront."
  }

  assert {
    condition = alltrue([
      for n in ["geo-blocking", "rate-limit-global", "body-size-limit", "aws-managed-sqli", "xss"] :
      contains([for r in aws_wafv2_web_acl.this.rule : r.name], n)
    ])
    error_message = "RULE waf-rules: geo blocking, rate limit, body size, SQLi and XSS rules are required."
  }

  assert {
    condition     = length(distinct([for r in aws_wafv2_web_acl.this.rule : r.priority])) == length(aws_wafv2_web_acl.this.rule)
    error_message = "RULE waf-priorities: rule priorities must be unique."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.default_action[0].allow != null
    error_message = "RULE waf-default: traffic not matched by a block rule is allowed."
  }
}

run "rate_limit_is_1000_per_5_minutes_by_ip" {
  command = plan

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-global" && r.statement[0].rate_based_statement[0].limit == 1000
      && r.statement[0].rate_based_statement[0].evaluation_window_sec == 300
      && r.statement[0].rate_based_statement[0].aggregate_key_type == "IP"
    ])
    error_message = "RULE rate-limit: 1000 requests per 5 minutes per IP."
  }
}

run "geo_blocking_allows_co_and_us_by_default" {
  command = plan

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "geo-blocking" && toset(r.statement[0].not_statement[0].statement[0].geo_match_statement[0].country_codes) == toset(["CO", "US"])
    ])
    error_message = "RULE geo: only CO and US are allowed by default."
  }
}

run "cloudfront_uses_https_only_and_is_linked_to_the_waf" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "RULE tls: viewers must be redirected to HTTPS."
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : o.custom_origin_config[0].origin_protocol_policy][0] == "https-only"
    error_message = "RULE origin-tls: CloudFront must reach the API Gateway over HTTPS only."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    error_message = "RULE no-cache: API responses must not be cached (CachingDisabled)."
  }
}

run "waf_outside_us_east_1_fails" {
  command = plan

  override_data {
    target = data.aws_region.current
    values = { region = "us-west-2" }
  }

  expect_failures = [aws_wafv2_web_acl.this]
}
