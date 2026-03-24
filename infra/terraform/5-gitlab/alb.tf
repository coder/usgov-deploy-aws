###############################################################################
# Layer 5 – ALB, WAF, Route 53 for GitLab
# coder4gov.com — Gov Demo Environment
#
# Creates:
#   - Internet-facing ALB in public subnets (GL-005)
#   - HTTPS listener with ACM wildcard cert (INFRA-005, INFRA-010)
#   - HTTP → HTTPS redirect
#   - Target group pointing to GitLab EC2 port 80
#   - WAF Web ACL with AWS Managed Rules (SEC-012)
#   - Route 53 A record: gitlab.coder4gov.com → ALB
#
# Requirements:
#   - GL-005: ALB + ACM TLS at gitlab.coder4gov.com with WAF
#   - SEC-012: AWS WAF with managed rules on all public ALBs
#   - INFRA-010: Route 53 + ACM
###############################################################################

locals {
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
  route53_zone_id   = data.terraform_remote_state.network.outputs.route53_zone_id
  acm_cert_arn      = data.terraform_remote_state.network.outputs.acm_wildcard_cert_arn
}

# ---------------------------------------------------------------------------
# Application Load Balancer — Internet-facing (GL-005)
# ---------------------------------------------------------------------------

resource "aws_lb" "gitlab" {
  name               = "${var.project_name}-gitlab"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.gitlab_alb.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = true
  drop_invalid_header_fields = true

  # Access logs to S3 (optional, uncomment when S3 log bucket exists)
  # access_logs {
  #   bucket  = "${var.project_name}-alb-logs"
  #   prefix  = "gitlab"
  #   enabled = true
  # }

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-alb"
  })
}

# ---------------------------------------------------------------------------
# Target Group — GitLab EC2 on port 80
# ALB terminates TLS and forwards HTTP to the instance
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "gitlab" {
  name     = "${var.project_name}-gitlab-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  # Health check — GitLab sign-in page
  health_check {
    enabled             = true
    path                = "/users/sign_in"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200,302"
  }

  # Stickiness for session consistency
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 24 hours
    enabled         = true
  }

  # Deregistration delay — give GitLab time to finish requests
  deregistration_delay = 120

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-tg"
  })
}

# ---------------------------------------------------------------------------
# HTTPS Listener (443) — ACM cert, default action → target group
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "gitlab_https" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab.arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-https"
  })
}

# ---------------------------------------------------------------------------
# HTTP Listener (80) — Redirect to HTTPS (INFRA-005)
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "gitlab_http_redirect" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-http-redirect"
  })
}

# ---------------------------------------------------------------------------
# WAF Web ACL — AWS Managed Rules (SEC-012)
# Attached to the GitLab ALB. Can be referenced by other layers.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "gitlab" {
  name        = "${var.project_name}-gitlab-waf"
  description = "WAF for GitLab ALB — AWS Managed Rules (SEC-012)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # -------------------------------------------------------------------------
  # Rule 1: AWS Managed Rules — Common Rule Set
  # Protects against common web exploits (XSS, SQLi, etc.)
  # -------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Exclude rules that may conflict with GitLab's large file uploads
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-gitlab-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Rule 2: AWS Managed Rules — Known Bad Inputs
  # Blocks requests with known malicious patterns
  # -------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-gitlab-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Rule 3: AWS Managed Rules — Bot Control
  # Manages bot traffic (allows verified bots, blocks scrapers)
  # -------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-gitlab-bot-control"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Rule 4: Rate limiting — Protect against brute force
  # -------------------------------------------------------------------------
  rule {
    name     = "RateLimitRule"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-gitlab-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-gitlab-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-waf"
  })
}

# Associate WAF Web ACL with the ALB
resource "aws_wafv2_web_acl_association" "gitlab" {
  resource_arn = aws_lb.gitlab.arn
  web_acl_arn  = aws_wafv2_web_acl.gitlab.arn
}

# ---------------------------------------------------------------------------
# WAF Logging — CloudWatch Logs (optional but recommended)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf_gitlab" {
  # WAF logging requires the log group name to start with "aws-waf-logs-"
  name              = "aws-waf-logs-${var.project_name}-gitlab"
  retention_in_days = 90

  tags = merge(var.tags, {
    Name = "aws-waf-logs-${var.project_name}-gitlab"
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "gitlab" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_gitlab.arn]
  resource_arn            = aws_wafv2_web_acl.gitlab.arn

  # Redact sensitive headers from logs
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# ---------------------------------------------------------------------------
# Route 53 — A record for gitlab.coder4gov.com → ALB (INFRA-010)
# ---------------------------------------------------------------------------

resource "aws_route53_record" "gitlab" {
  zone_id = local.route53_zone_id
  name    = "gitlab.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.gitlab.dns_name
    zone_id                = aws_lb.gitlab.zone_id
    evaluate_target_health = true
  }
}
