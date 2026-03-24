###############################################################################
# Layer 5 – Security Groups for GitLab
# coder4gov.com — Gov Demo Environment
#
# Two security groups:
#   1. ALB SG — public-facing, accepts HTTPS from the internet
#   2. GitLab SG — private, accepts traffic only from the ALB
#
# Requirements:
#   - INFRA-009: Least-privilege security groups
#   - GL-005:  ALB + ACM TLS at gitlab.coder4gov.com
#   - GL-016:  SSH disabled — NO port 22 ingress
###############################################################################

locals {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}

# ---------------------------------------------------------------------------
# ALB Security Group
# Accepts HTTPS (443) from the internet, forwards to GitLab on 443
# ---------------------------------------------------------------------------

resource "aws_security_group" "gitlab_alb" {
  name_prefix = "${var.project_name}-gitlab-alb-"
  description = "GitLab ALB — public HTTPS ingress (SEC-012, GL-005)"
  vpc_id      = local.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https_in" {
  security_group_id = aws_security_group.gitlab_alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-https-in" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_in" {
  security_group_id = aws_security_group.gitlab_alb.id
  description       = "HTTP from internet (redirects to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-http-in" }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_gitlab" {
  security_group_id            = aws_security_group.gitlab_alb.id
  description                  = "Forward to GitLab instances on port 80"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.gitlab_instance.id

  tags = { Name = "alb-to-gitlab" }
}

# ---------------------------------------------------------------------------
# GitLab Instance Security Group
# Accepts traffic ONLY from the ALB — NO SSH (GL-016)
# ---------------------------------------------------------------------------

resource "aws_security_group" "gitlab_instance" {
  name_prefix = "${var.project_name}-gitlab-ec2-"
  description = "GitLab EC2 — ALB traffic only, NO SSH (GL-016)"
  vpc_id      = local.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-ec2"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: HTTP from ALB only (ALB terminates TLS, forwards on port 80)
resource "aws_vpc_security_group_ingress_rule" "gitlab_from_alb" {
  security_group_id            = aws_security_group.gitlab_instance.id
  description                  = "HTTP from ALB (TLS terminated at ALB)"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.gitlab_alb.id

  tags = { Name = "gitlab-from-alb" }
}

# NOTE: NO port 22 rule — SSH is disabled per GL-016.
# Admin access is via SSM Session Manager only.

# Egress: All outbound (package downloads, S3, SES, ECR, etc.)
resource "aws_vpc_security_group_egress_rule" "gitlab_all_out" {
  security_group_id = aws_security_group.gitlab_instance.id
  description       = "All outbound (S3, SES, ECR, package repos)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "gitlab-all-out" }
}

# ---------------------------------------------------------------------------
# Optional: SSH during initial setup (empty by default per GL-016)
# Controlled via var.allowed_ssh_cidrs — set to [] after setup.
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "gitlab_ssh_setup" {
  count = length(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.gitlab_instance.id
  description       = "SSH for initial setup ONLY — remove after (GL-016)"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidrs[count.index]

  tags = { Name = "gitlab-ssh-setup-${count.index}" }
}
