################################################################################
# Outputs – Layer 2 Data
# Consumed by Layer 3 (EKS) and Layer 4 (Applications)
################################################################################

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------
output "kms_key_arn" {
  description = "ARN of the KMS Customer Managed Key."
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "Key ID of the KMS Customer Managed Key."
  value       = aws_kms_key.main.key_id
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------
output "rds_endpoint" {
  description = "RDS instance endpoint (hostname only)."
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS instance port."
  value       = aws_db_instance.main.port
}

output "rds_master_username" {
  description = "RDS master username."
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "rds_master_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master password."
  value       = aws_secretsmanager_secret.rds_master_password.arn
}

output "rds_security_group_id" {
  description = "Security group ID attached to the RDS instance."
  value       = aws_security_group.rds.id
}

# ---------------------------------------------------------------------------
# S3 Buckets
# ---------------------------------------------------------------------------
output "s3_gitlab_bucket" {
  description = "Name of the GitLab backups S3 bucket."
  value       = aws_s3_bucket.gitlab_backups.id
}

output "s3_gitlab_bucket_arn" {
  description = "ARN of the GitLab backups S3 bucket."
  value       = aws_s3_bucket.gitlab_backups.arn
}

output "s3_loki_bucket" {
  description = "Name of the Loki logs S3 bucket."
  value       = aws_s3_bucket.loki_logs.id
}

output "s3_loki_bucket_arn" {
  description = "ARN of the Loki logs S3 bucket."
  value       = aws_s3_bucket.loki_logs.arn
}

output "s3_general_bucket" {
  description = "Name of the general artifacts S3 bucket."
  value       = aws_s3_bucket.general.id
}

output "s3_general_bucket_arn" {
  description = "ARN of the general artifacts S3 bucket."
  value       = aws_s3_bucket.general.arn
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
output "ecr_coder_repo_url" {
  description = "ECR repository URL for the FIPS Coder image."
  value       = aws_ecr_repository.repos["coder"].repository_url
}

output "ecr_base_fips_repo_url" {
  description = "ECR repository URL for the FIPS base workspace image."
  value       = aws_ecr_repository.repos["base-fips"].repository_url
}

output "ecr_desktop_fips_repo_url" {
  description = "ECR repository URL for the FIPS desktop workspace image."
  value       = aws_ecr_repository.repos["desktop-fips"].repository_url
}

output "ecr_repo_urls" {
  description = "Map of all ECR repository URLs."
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}

# ---------------------------------------------------------------------------
# SES
# ---------------------------------------------------------------------------
output "ses_smtp_endpoint" {
  description = "SES SMTP endpoint for sending email."
  value       = "email-smtp.${var.aws_region}.amazonaws.com"
}

output "ses_domain_identity_arn" {
  description = "ARN of the SES domain identity."
  value       = aws_ses_domain_identity.main.arn
}

# ---------------------------------------------------------------------------
# Secrets Manager – ARN map
# ---------------------------------------------------------------------------
output "secret_arns" {
  description = "Map of Secrets Manager secret ARNs."
  value = {
    rds_master_password  = aws_secretsmanager_secret.rds_master_password.arn
    openai_api_key       = aws_secretsmanager_secret.openai_api_key.arn
    gemini_api_key       = aws_secretsmanager_secret.gemini_api_key.arn
    coder_license        = aws_secretsmanager_secret.coder_license.arn
    ses_smtp_credentials = aws_secretsmanager_secret.ses_smtp_credentials.arn
  }
}
