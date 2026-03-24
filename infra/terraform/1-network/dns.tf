###############################################################################
# Layer 1 – Route 53 & ACM Certificates
# coder4gov.com — Gov Demo Environment
#
# Creates:
#   - Route 53 public hosted zone for coder4gov.com (INFRA-010)
#   - ACM wildcard certificate for *.coder4gov.com
#   - ACM apex certificate for coder4gov.com
#   - DNS validation records
#
# The domain is registered through AWS Route 53 (Decision #1, #2), so the
# zone just needs to exist — no delegation required.
###############################################################################

# ---------------------------------------------------------------------------
# Route 53 Hosted Zone
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "${var.project_name} – primary public zone (AWS-registered domain)"

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-zone"
  })
}

# ---------------------------------------------------------------------------
# ACM — Wildcard Certificate (*.coder4gov.com)
#
# Covers: dev.coder4gov.com, *.dev.coder4gov.com, gitlab.coder4gov.com,
#         sso.coder4gov.com, grafana.dev.coder4gov.com, etc.
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-wildcard-cert"
  })
}

# ---------------------------------------------------------------------------
# ACM — Apex Certificate (coder4gov.com)
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "apex" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-apex-cert"
  })
}

# ---------------------------------------------------------------------------
# DNS Validation Records — Wildcard
# ---------------------------------------------------------------------------

resource "aws_route53_record" "wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.wildcard_validation : record.fqdn]
}

# ---------------------------------------------------------------------------
# DNS Validation Records — Apex
# ---------------------------------------------------------------------------

resource "aws_route53_record" "apex_validation" {
  for_each = {
    for dvo in aws_acm_certificate.apex.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "apex" {
  certificate_arn         = aws_acm_certificate.apex.arn
  validation_record_fqdns = [for record in aws_route53_record.apex_validation : record.fqdn]
}
