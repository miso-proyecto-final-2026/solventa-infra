# CloudFront (termina TLS y acerca el borde al cliente) con el WAF vinculado, delante del API Gateway.
# Reglas de la sección 5.3 de la documentación técnica: SQLi, XSS, rate limiting global, geo blocking y tamaño de cuerpo.
# Un WAF de alcance CLOUDFRONT solo se crea en us-east-1: el proveedor de este módulo debe estar en esa región.

data "aws_region" "current" {}

locals {
  # 256 KB = 262144 bytes. Content-Length es texto: se bloquean los de 7 o más dígitos y los de 6 dígitos mayores que 262144.
  content_length_over_256kb = "^([0-9]{7,}|[3-9][0-9]{5}|2[7-9][0-9]{4}|26[3-9][0-9]{3}|262[2-9][0-9]{2}|2621[5-9][0-9]|26214[5-9])$"
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-edge"
  description = "WAF del borde publico de Solventa"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 1. Geo blocking: bloquea el tráfico de fuera de los países permitidos.
  rule {
    name     = "geo-blocking"
    priority = 1

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = var.allowed_countries
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "geo-blocking"
      sampled_requests_enabled   = true
    }
  }

  # 2. Rate limiting global por IP.
  rule {
    name     = "rate-limit-global"
    priority = 2

    action {
      block {
        custom_response {
          response_code = 429
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_per_5min
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"

        # Las rutas de alto volumen tienen su propia regla (más abajo): aquí no cuentan.
        dynamic "scope_down_statement" {
          for_each = var.high_volume_path_regex == "" ? [] : [1]

          content {
            not_statement {
              statement {
                regex_match_statement {
                  regex_string = var.high_volume_path_regex

                  field_to_match {
                    uri_path {}
                  }

                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-global"
      sampled_requests_enabled   = true
    }
  }

  # 3. Límite de cuerpo de 256 KB, salvo la subida de verificación de identidad.
  rule {
    name     = "body-size-limit"
    priority = 3

    action {
      block {
        custom_response {
          response_code = 413
        }
      }
    }

    statement {
      and_statement {
        statement {
          regex_match_statement {
            regex_string = local.content_length_over_256kb

            field_to_match {
              single_header {
                name = "content-length"
              }
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              regex_match_statement {
                regex_string = var.exempt_body_path_regex

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "body-size-limit"
      sampled_requests_enabled   = true
    }
  }

  # 4. SQL injection (conjunto administrado de AWS), sin inspeccionar la subida binaria de KYC.
  rule {
    name     = "aws-managed-sqli"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"

        scope_down_statement {
          not_statement {
            statement {
              regex_match_statement {
                regex_string = var.exempt_body_path_regex

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-sqli"
      sampled_requests_enabled   = true
    }
  }

  # 5. XSS en la ruta, la consulta y el cuerpo (el cuerpo de la subida de KYC queda exento).
  rule {
    name     = "xss"
    priority = 5

    action {
      block {}
    }

    statement {
      or_statement {
        statement {
          xss_match_statement {
            field_to_match {
              query_string {}
            }

            text_transformation {
              priority = 0
              type     = "URL_DECODE"
            }

            text_transformation {
              priority = 1
              type     = "HTML_ENTITY_DECODE"
            }
          }
        }

        statement {
          xss_match_statement {
            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "URL_DECODE"
            }

            text_transformation {
              priority = 1
              type     = "HTML_ENTITY_DECODE"
            }
          }
        }

        statement {
          and_statement {
            statement {
              xss_match_statement {
                field_to_match {
                  body {
                    oversize_handling = "CONTINUE"
                  }
                }

                text_transformation {
                  priority = 0
                  type     = "HTML_ENTITY_DECODE"
                }
              }
            }

            statement {
              not_statement {
                statement {
                  regex_match_statement {
                    regex_string = var.exempt_body_path_regex

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "xss"
      sampled_requests_enabled   = true
    }
  }

  # 6. Límite por IP propio de las rutas de alto volumen (proveedores de eventos): más alto que el global, pero no infinito.
  dynamic "rule" {
    for_each = var.high_volume_path_regex == "" ? [] : [1]

    content {
      name     = "rate-limit-high-volume"
      priority = 6

      action {
        block {
          custom_response {
            response_code = 429
          }
        }
      }

      statement {
        rate_based_statement {
          limit                 = var.high_volume_rate_limit_per_5min
          evaluation_window_sec = 300
          aggregate_key_type    = "IP"

          scope_down_statement {
            regex_match_statement {
              regex_string = var.high_volume_path_regex

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "rate-limit-high-volume"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-edge"
    sampled_requests_enabled   = true
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == "us-east-1"
      error_message = "El WAF de alcance CLOUDFRONT solo existe en us-east-1; este módulo debe usar un proveedor de esa región."
    }
  }
}

locals {
  # Con la consola web (HU39), el origen por defecto es el bucket y la API queda en /v1/* y /api/*.
  web_enabled = var.enable_web

  # Políticas administradas de AWS. La API no se cachea y reenvía todo salvo el Host.
  cache_disabled                = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  cache_optimized               = "658327ea-f89d-4aba-9e8a-1ab1e5a1ee5a"
  all_viewer_except_host_header = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  all_methods                   = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
}

resource "aws_cloudfront_origin_access_control" "web" {
  count = local.web_enabled ? 1 : 0

  name                              = "${var.name}-web"
  description                       = "CloudFront firma las lecturas del bucket de la consola web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "api_prefix" {
  count = local.web_enabled ? 1 : 0

  name    = "${var.name}-api-prefix"
  comment = "Quita /api/<servicio> de las llamadas de la consola web"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/api-prefix.js")
}

resource "aws_cloudfront_function" "web_spa" {
  count = local.web_enabled ? 1 : 0

  name    = "${var.name}-web-spa"
  comment = "Sirve el index.html de cada idioma en las rutas de la consola web"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/web-spa.js")
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = "${var.name}: borde publico de Solventa"
  http_version    = "http2and3"
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  web_acl_id      = aws_wafv2_web_acl.this.arn

  origin {
    origin_id   = "api-gateway"
    domain_name = var.origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  dynamic "origin" {
    for_each = local.web_enabled ? [1] : []

    content {
      origin_id                = "web"
      domain_name              = var.web_origin_domain
      origin_access_control_id = aws_cloudfront_origin_access_control.web[0].id
    }
  }

  # Sin consola web, todo va a la API. Con ella, el resto de rutas son archivos estáticos cacheables.
  default_cache_behavior {
    target_origin_id         = local.web_enabled ? "web" : "api-gateway"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = local.web_enabled ? ["GET", "HEAD"] : local.all_methods
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = local.web_enabled ? local.cache_optimized : local.cache_disabled
    origin_request_policy_id = local.web_enabled ? null : local.all_viewer_except_host_header

    dynamic "function_association" {
      for_each = local.web_enabled ? [1] : []

      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.web_spa[0].arn
      }
    }
  }

  # La app móvil y los proveedores siguen llamando a /v1/* tal cual.
  dynamic "ordered_cache_behavior" {
    for_each = local.web_enabled ? [1] : []

    content {
      path_pattern             = "/v1/*"
      target_origin_id         = "api-gateway"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = local.all_methods
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      cache_policy_id          = local.cache_disabled
      origin_request_policy_id = local.all_viewer_except_host_header
    }
  }

  # La consola web llama a /api/<servicio>/v1/*: la función deja solo /v1/*.
  dynamic "ordered_cache_behavior" {
    for_each = local.web_enabled ? [1] : []

    content {
      path_pattern             = "/api/*"
      target_origin_id         = "api-gateway"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = local.all_methods
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      cache_policy_id          = local.cache_disabled
      origin_request_policy_id = local.all_viewer_except_host_header

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.api_prefix[0].arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}
