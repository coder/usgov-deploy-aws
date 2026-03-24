################################################################################
# WAF v2 Web ACL — EKS Services
# coder4gov.com — Gov Demo Environment
#
# SEC-010: AWS Managed Common Rule Set
# SEC-011: AWS Managed Known Bad Inputs Rule Set
# SEC-012: AWS Managed Bot Control Rule Set
# SEC-013: IP restriction for Keycloak /admin paths
#
# The ACL ARN is output so Ingress annotations can associate it with the ALB
# created by the AWS Load Balancer Controller.
################################################################################

# ---------------------------------------------------------------------------
# SEC-013: IP Set for admin CIDR allowlist (used only when populated)
# ---------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "admin_allowlist" {
  count = length(var.allowed_admin_cidrs) > 0 ? 1 : 0

  name               = "${var.project_name}-admin-allowlist"
  description        = "CIDR blocks allowed to reach Keycloak /admin endpoints."
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_admin_cidrs

  tags = {
    Component = "waf"
  }
}

# ---------------------------------------------------------------------------
# Web ACL
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "eks" {
  name        = "${var.project_name}-eks-waf"
  description = "WAF Web ACL for EKS-hosted services (Coder, Keycloak, LiteLLM)."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # -------------------------------------------------------------------------
  # SEC-013: Block non-allowlisted IPs hitting Keycloak /admin (priority 5)
  # Only created when allowed_admin_cidrs is non-empty.
  # -------------------------------------------------------------------------
  dynamic "rule" {
    for_each = length(var.allowed_admin_cidrs) > 0 ? [1] : []

    content {
      name     = "keycloak-admin-ip-restriction"
      priority = 5

      action {
        block {}
      }

      statement {
        and_statement {
          statement {
            # Match requests to /admin paths
            byte_match_statement {
              search_string         = "/admin"
              positional_constraint = "STARTS_WITH"
              field_to_match {
                uri_path {}
              }
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
          statement {
            # NOT in the allowlist → block
            not_statement {
              statement {
                ip_set_reference_statement {
                  arn = aws_wafv2_ip_set.admin_allowlist[0].arn
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-keycloak-admin-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  # -------------------------------------------------------------------------
  # SEC-010: AWS Managed Common Rule Set (priority 10)
  # -------------------------------------------------------------------------
  rule {
    name     = "aws-common-rules"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # SEC-011: AWS Managed Known Bad Inputs Rule Set (priority 20)
  # -------------------------------------------------------------------------
  rule {
    name     = "aws-known-bad-inputs"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # SEC-012: AWS Managed Bot Control Rule Set (priority 30)
  # -------------------------------------------------------------------------
  rule {
    name     = "aws-bot-control"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesBotControlRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # Visibility config for the ACL itself
  # -------------------------------------------------------------------------
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-eks-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Component = "waf"
  }
}
