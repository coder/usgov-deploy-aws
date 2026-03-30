# KMS
output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "kms_key_id" {
  value = aws_kms_key.main.key_id
}

# RDS
output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_port" {
  value = aws_db_instance.main.port
}

output "rds_master_username" {
  value     = aws_db_instance.main.username
  sensitive = true
}

output "rds_master_password_secret_arn" {
  value = aws_secretsmanager_secret.rds_master_password.arn
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

# ECR
output "ecr_coder_repo_url" {
  value = aws_ecr_repository.repos["coder"].repository_url
}

output "ecr_base_fips_repo_url" {
  value = aws_ecr_repository.repos["base-fips"].repository_url
}

output "ecr_desktop_fips_repo_url" {
  value = aws_ecr_repository.repos["desktop-fips"].repository_url
}

output "ecr_repo_urls" {
  value = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}

# Secrets Manager – ARN map
output "secret_arns" {
  value = {
    rds_master_password = aws_secretsmanager_secret.rds_master_password.arn
    coder_license       = aws_secretsmanager_secret.coder_license.arn
  }
}

# CI/CD — store these as GitHub repo secrets
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions CI (set as AWS_ROLE_ARN secret)."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_registry" {
  description = "ECR registry URL (set as ECR_REGISTRY secret)."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}
