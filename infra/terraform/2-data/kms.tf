################################################################################
# KMS – Customer Managed Key for data-layer encryption
# Used by: RDS, S3, Secrets Manager, EBS, ECR
################################################################################

resource "aws_kms_key" "main" {
  description             = "${var.project_name} CMK – encrypts RDS, S3, Secrets Manager, EBS, ECR"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.project_name}-key-policy"
    Statement = [
      # ---------------------------------------------------------------
      # Root account – full admin access to the key
      # ---------------------------------------------------------------
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # ---------------------------------------------------------------
      # Allow EKS service-linked role to use the key (for EBS
      # encryption of PVCs and node volumes)
      # ---------------------------------------------------------------
      {
        Sid    = "AllowEKSServiceRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant",
        ]
        Resource = "*"
      },
      # ---------------------------------------------------------------
      # Allow AWS services (RDS, S3, Secrets Manager, EBS, ECR) to use
      # the key via service-linked grant mechanism
      # ---------------------------------------------------------------
      {
        Sid    = "AllowAWSServicesViaGrant"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant",
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${var.project_name}-cmk"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.main.key_id
}
