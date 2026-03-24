################################################################################
# SES – Domain & Email Identity, DKIM, SPF, DMARC
################################################################################

# ---------------------------------------------------------------------------
# Data source: Route 53 hosted zone from Layer 1
# ---------------------------------------------------------------------------
data "aws_route53_zone" "main" {
  zone_id = local.route53_zone_id
}

# ---------------------------------------------------------------------------
# SES Domain Identity
# ---------------------------------------------------------------------------
resource "aws_ses_domain_identity" "main" {
  domain = var.domain_name
}

# Route 53 TXT record for SES domain verification
resource "aws_route53_record" "ses_verification" {
  zone_id = local.route53_zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.main.verification_token]
}

resource "aws_ses_domain_identity_verification" "main" {
  domain = aws_ses_domain_identity.main.id

  depends_on = [aws_route53_record.ses_verification]
}

# ---------------------------------------------------------------------------
# DKIM
# ---------------------------------------------------------------------------
resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

resource "aws_route53_record" "ses_dkim" {
  count = 3

  zone_id = local.route53_zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ---------------------------------------------------------------------------
# SPF Record (via SES custom MAIL FROM domain)
# ---------------------------------------------------------------------------
resource "aws_ses_domain_mail_from" "main" {
  domain           = aws_ses_domain_identity.main.domain
  mail_from_domain = "mail.${var.domain_name}"
}

resource "aws_route53_record" "ses_spf_mail_from" {
  zone_id = local.route53_zone_id
  name    = "mail.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = local.route53_zone_id
  name    = "mail.${var.domain_name}"
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

# ---------------------------------------------------------------------------
# DMARC Record
# ---------------------------------------------------------------------------
resource "aws_route53_record" "dmarc" {
  zone_id = local.route53_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@${var.domain_name}; pct=100"]
}

# ---------------------------------------------------------------------------
# Email Identity – noreply@coder4gov.com
# ---------------------------------------------------------------------------
resource "aws_ses_email_identity" "noreply" {
  email = "noreply@${var.domain_name}"
}

# ---------------------------------------------------------------------------
# SMTP Credentials (IAM user scoped to SES only)
# ---------------------------------------------------------------------------
resource "aws_iam_user" "ses_smtp" {
  name = "${var.project_name}-ses-smtp"
  path = "/system/"

  tags = {
    Name    = "${var.project_name}-ses-smtp"
    Purpose = "SES SMTP relay credentials"
  }
}

resource "aws_iam_user_policy" "ses_smtp" {
  name = "${var.project_name}-ses-send"
  user = aws_iam_user.ses_smtp.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}
