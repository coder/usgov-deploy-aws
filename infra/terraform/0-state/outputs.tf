###############################################################################
# Layer 0 – Outputs
# coder4gov.com — Gov Demo Environment
#
# These outputs are consumed by all subsequent layers via their S3 backend
# configuration and data sources.
###############################################################################

output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket storing Terraform state."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.terraform_lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for state encryption."
  value       = aws_kms_key.terraform_state.arn
}
