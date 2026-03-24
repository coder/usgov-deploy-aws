################################################################################
# S3 Buckets
# All buckets: SSE-KMS with CMK, block all public access
################################################################################

# ===========================================================================
# 1. GitLab Backups  (versioning ENABLED)
# ===========================================================================
resource "aws_s3_bucket" "gitlab_backups" {
  bucket = "${var.project_name}-gitlab-backups"

  tags = {
    Name    = "${var.project_name}-gitlab-backups"
    Purpose = "GitLab backups, LFS, artifacts"
  }
}

resource "aws_s3_bucket_versioning" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "gitlab_backups" {
  bucket = aws_s3_bucket.gitlab_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ===========================================================================
# 2. Loki Logs  (lifecycle: transition to IA after 90 days)
# ===========================================================================
resource "aws_s3_bucket" "loki_logs" {
  bucket = "${var.project_name}-loki-logs"

  tags = {
    Name    = "${var.project_name}-loki-logs"
    Purpose = "Loki log storage"
  }
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# ===========================================================================
# 3. General Artifacts
# ===========================================================================
resource "aws_s3_bucket" "general" {
  bucket = "${var.project_name}-general"

  tags = {
    Name    = "${var.project_name}-general"
    Purpose = "General artifacts"
  }
}

resource "aws_s3_bucket_versioning" "general" {
  bucket = aws_s3_bucket.general.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "general" {
  bucket = aws_s3_bucket.general.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "general" {
  bucket = aws_s3_bucket.general.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
