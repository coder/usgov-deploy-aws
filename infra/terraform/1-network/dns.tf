###############################################################################
# Layer 1 – Route 53 & ACM Certificates
# coder4gov.com — Gov Demo Environment
#
# Uses the existing Route 53 hosted zone created by domain registration.
# Creates:
#   - ACM wildcard certificate for *.coder4gov.com + *.dev.coder4gov.com
#   - ACM apex certificate for coder4gov.com
#   - DNS validation records
###############################################################################

# ---------------------------------------------------------------------------
# Route 53 Hosted Zone — look up the zone created by domain registration.
# No zone is created; we just reference the existing one.
# ---------------------------------------------------------------------------

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ---------------------------------------------------------------------------
# ACM — Wildcard Certificate
#
# Covers:
#   *.coder4gov.com       — top-level services (dev, sso, gitlab, grafana)
#   *.dev.coder4gov.com   — Coder workspace app subdomains
#   coder4gov.com         — apex
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "wildcard" {
  domain_name = "*.${var.domain_name}"
  subject_alternative_names = [
    var.domain_name,
    "*.dev.${var.domain_name}",
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.all_tags, {
    Name = "${var.project_name}-wildcard-cert"
  })
}

# ---------------------------------------------------------------------------
# DNS Validation Records
#
# Uses -target on first apply to resolve the for_each chicken-and-egg:
#   terraform apply -target=aws_acm_certificate.wildcard
#   terraform apply
# ---------------------------------------------------------------------------

resource "aws_route53_record" "cert_validation" {
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
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
