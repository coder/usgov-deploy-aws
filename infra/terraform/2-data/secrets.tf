# 1. RDS Master Password
resource "aws_secretsmanager_secret" "rds_master_password" {
  name       = "${var.project_name}/rds-master-password"
  kms_key_id = aws_kms_key.main.arn
}
resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id = aws_secretsmanager_secret.rds_master_password.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.rds_master.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}

# 2. Coder License (placeholder)
resource "aws_secretsmanager_secret" "coder_license" {
  name       = "${var.project_name}/coder-license"
  kms_key_id = aws_kms_key.main.arn
}
resource "aws_secretsmanager_secret_version" "coder_license" {
  secret_id     = aws_secretsmanager_secret.coder_license.id
  secret_string = jsonencode({ license = "PLACEHOLDER_SET_MANUALLY" })
}
