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

run "waf_description_matches_the_wafv2_pattern" {
  command = plan

  # WAFv2 rechaza las tildes en la descripción (ValidationException).
  assert {
    condition     = can(regex("^[\\w+=:#@/\\-,\\.][\\w+=:#@/\\-,\\.\\s]+[\\w+=:#@/\\-,\\.]$", aws_wafv2_web_acl.this.description))
    error_message = "RULE waf-charset: the WAF description must match the WAFv2 pattern (no accents)."
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

run "without_high_volume_paths_the_waf_keeps_only_the_global_rate_limit" {
  command = plan

  assert {
    condition     = !contains([for r in aws_wafv2_web_acl.this.rule : r.name], "rate-limit-high-volume")
    error_message = "RULE waf-high-volume: with no high-volume path there is no extra rate rule."
  }
}

run "high_volume_paths_get_their_own_rate_limit_and_leave_the_global_one" {
  command = plan

  variables {
    high_volume_path_regex = "^(/v1/siniestros)(/.*)?$"
  }

  assert {
    condition = (
      contains([for r in aws_wafv2_web_acl.this.rule : r.name], "rate-limit-high-volume")
      && length(distinct([for r in aws_wafv2_web_acl.this.rule : r.priority])) == length(aws_wafv2_web_acl.this.rule)
    )
    error_message = "RULE waf-high-volume: a high-volume path adds its own rate rule with a unique priority."
  }

  assert {
    condition = (
      [for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-limit-high-volume"][0] == 600000
      && [for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-limit-global"][0] == 1000
    )
    error_message = "RULE waf-high-volume: 600000 per 5 min for the high-volume path; the global limit stays at 1000."
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit-global" && length(r.statement[0].rate_based_statement[0].scope_down_statement) == 1]) == 1
    error_message = "RULE waf-high-volume: the global rate rule must not count the high-volume paths (scope-down)."
  }
}

run "without_web_everything_goes_to_the_api" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].target_origin_id == "api-gateway"
    error_message = "RULE edge-api-default: without the web console the default behavior must reach the API Gateway."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 0
    error_message = "RULE edge-api-default: without the web console there are no extra behaviors."
  }
}

run "web_console_keeps_the_api_uncached_and_unchanged_for_mobile" {
  command = plan

  variables {
    enable_web        = true
    web_origin_domain = "solventa-staging-web-123.s3.us-east-1.amazonaws.com"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].target_origin_id == "web"
    error_message = "RULE edge-web-default: with the web console the default behavior must reach the bucket."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods) == toset(["GET", "HEAD"])
    error_message = "RULE edge-web-readonly: the bucket origin must only accept reads."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.target_origin_id == "api-gateway" && b.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    ])
    error_message = "RULE edge-api-no-cache: API behaviors must reach the API Gateway without caching."
  }

  assert {
    condition     = toset([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.path_pattern]) == toset(["/v1/*", "/api/*"])
    error_message = "RULE edge-api-paths: the API must stay under /v1/* (mobile) and /api/* (web console)."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.path_pattern != "/v1/*" || length(b.function_association) == 0
    ])
    error_message = "RULE edge-mobile-unchanged: /v1/* must not be rewritten."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.web[0].signing_behavior == "always"
    error_message = "RULE edge-web-oac: CloudFront must sign its reads of the web bucket."
  }
}
