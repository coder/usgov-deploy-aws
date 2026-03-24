###############################################################################
# Layer 5 – Outputs
# coder4gov.com — Gov Demo Environment
#
# These outputs are consumed by subsequent layers and for operational use.
###############################################################################

output "gitlab_url" {
  description = "GitLab CE URL (HTTPS via ALB)."
  value       = "https://gitlab.${var.domain_name}"
}

output "gitlab_alb_dns_name" {
  description = "DNS name of the GitLab ALB (for troubleshooting)."
  value       = aws_lb.gitlab.dns_name
}

output "gitlab_alb_arn" {
  description = "ARN of the GitLab ALB."
  value       = aws_lb.gitlab.arn
}

output "gitlab_asg_name" {
  description = "Name of the GitLab Auto Scaling Group."
  value       = aws_autoscaling_group.gitlab.name
}

output "gitlab_instance_profile_arn" {
  description = "ARN of the GitLab EC2 instance profile."
  value       = aws_iam_instance_profile.gitlab.arn
}

output "gitlab_instance_role_arn" {
  description = "ARN of the GitLab EC2 IAM role."
  value       = aws_iam_role.gitlab.arn
}

output "gitlab_security_group_id" {
  description = "Security group ID for the GitLab EC2 instance."
  value       = aws_security_group.gitlab_instance.id
}

output "gitlab_alb_security_group_id" {
  description = "Security group ID for the GitLab ALB."
  value       = aws_security_group.gitlab_alb.id
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL. Can be referenced by other layers for reuse patterns."
  value       = aws_wafv2_web_acl.gitlab.arn
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL."
  value       = aws_wafv2_web_acl.gitlab.id
}

output "gitlab_target_group_arn" {
  description = "ARN of the GitLab ALB target group."
  value       = aws_lb_target_group.gitlab.arn
}

output "gitlab_route53_fqdn" {
  description = "Fully qualified domain name for GitLab in Route 53."
  value       = aws_route53_record.gitlab.fqdn
}
