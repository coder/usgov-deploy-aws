################################################################################
# Secrets Manager – all sensitive values encrypted with KMS CMK
################################################################################

# ---------------------------------------------------------------------------
# 1. RDS Master Password (from random_password in rds.tf)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "rds_master_password" {
  name       = "${var.project_name}/rds-master-password"
  kms_key_id = aws_kms_key.main.arn

  description = "Master password for the ${var.project_name} RDS PostgreSQL instance"

  tags = {
    Name = "${var.project_name}/rds-master-password"
  }
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

# ---------------------------------------------------------------------------
# 2. OpenAI API Key (placeholder – set manually after creation)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "openai_api_key" {
  name       = "${var.project_name}/openai-api-key"
  kms_key_id = aws_kms_key.main.arn

  description = "OpenAI API key for LiteLLM proxy"

  tags = {
    Name = "${var.project_name}/openai-api-key"
  }
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = jsonencode({ api_key = "PLACEHOLDER_SET_MANUALLY" })
}

# ---------------------------------------------------------------------------
# 3. Gemini API Key (placeholder – set manually after creation)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "gemini_api_key" {
  name       = "${var.project_name}/gemini-api-key"
  kms_key_id = aws_kms_key.main.arn

  description = "Google Gemini API key for LiteLLM proxy"

  tags = {
    Name = "${var.project_name}/gemini-api-key"
  }
}

resource "aws_secretsmanager_secret_version" "gemini_api_key" {
  secret_id     = aws_secretsmanager_secret.gemini_api_key.id
  secret_string = jsonencode({ api_key = "PLACEHOLDER_SET_MANUALLY" })
}

# ---------------------------------------------------------------------------
# 4. Coder License (placeholder – set manually after creation)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "coder_license" {
  name       = "${var.project_name}/coder-license"
  kms_key_id = aws_kms_key.main.arn

  description = "Coder enterprise license key"

  tags = {
    Name = "${var.project_name}/coder-license"
  }
}

resource "aws_secretsmanager_secret_version" "coder_license" {
  secret_id     = aws_secretsmanager_secret.coder_license.id
  secret_string = jsonencode({ license = "PLACEHOLDER_SET_MANUALLY" })
}

# ---------------------------------------------------------------------------
# 5. SES SMTP Credentials (from IAM access key in ses.tf)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "ses_smtp_credentials" {
  name       = "${var.project_name}/ses-smtp-credentials"
  kms_key_id = aws_kms_key.main.arn

  description = "SES SMTP credentials for outbound email"

  tags = {
    Name = "${var.project_name}/ses-smtp-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "ses_smtp_credentials" {
  secret_id = aws_secretsmanager_secret.ses_smtp_credentials.id
  secret_string = jsonencode({
    smtp_username = aws_iam_access_key.ses_smtp.id
    smtp_password = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
    smtp_endpoint = "email-smtp.${var.aws_region}.amazonaws.com"
    smtp_port     = 587
  })
}
