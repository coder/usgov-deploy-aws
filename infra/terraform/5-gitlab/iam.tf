###############################################################################
# Layer 5 – IAM for GitLab EC2
# coder4gov.com — Gov Demo Environment
#
# Creates an instance profile with least-privilege access to:
#   - S3: gitlab-backups + gitlab-artifacts buckets (GL-004, GL-008)
#   - ECR: push/pull for Docker runner builds (GL-011)
#   - SES: send email for notifications (GL-015)
#   - Secrets Manager: read SES creds, OIDC secrets (SM-001)
#   - SSM: Session Manager access for admin without SSH (GL-016)
#
# Requirement traceability: EKS-006 (IRSA for K8s), SEC-004 (no static keys).
# EC2 uses instance profile — no static IAM keys.
###############################################################################

# ---------------------------------------------------------------------------
# IAM Role — GitLab EC2
# ---------------------------------------------------------------------------

resource "aws_iam_role" "gitlab" {
  name = "${var.project_name}-gitlab-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-ec2"
  })
}

# ---------------------------------------------------------------------------
# IAM Instance Profile
# ---------------------------------------------------------------------------

resource "aws_iam_instance_profile" "gitlab" {
  name = "${var.project_name}-gitlab-ec2"
  role = aws_iam_role.gitlab.name

  tags = merge(var.tags, {
    Name = "${var.project_name}-gitlab-ec2"
  })
}

# ---------------------------------------------------------------------------
# Policy: S3 Access — GitLab backups + object storage (GL-004, GL-008)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "gitlab_s3" {
  name = "gitlab-s3-access"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        Resource = [
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-backups",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-backups/*",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-artifacts",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-artifacts/*",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-lfs",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-lfs/*",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-uploads",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-uploads/*",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-packages",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-packages/*",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-registry",
          "arn:${var.aws_partition}:s3:::${var.project_name}-gitlab-registry/*",
        ]
      },
      {
        Sid    = "S3KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = [
          data.terraform_remote_state.data.outputs.kms_key_arn,
        ]
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Policy: ECR Push/Pull — Docker runner image builds (GL-011)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "gitlab_ecr" {
  name = "gitlab-ecr-access"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
        ]
        Resource = "arn:${var.aws_partition}:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Policy: SES — Send email for GitLab notifications (GL-015, INFRA-013)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "gitlab_ses" {
  name = "gitlab-ses-send"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SESSendEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
        ]
        Resource = "arn:${var.aws_partition}:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/${var.domain_name}"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Policy: Secrets Manager — Read SES creds, OIDC client secrets (SM-001)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "gitlab_secrets" {
  name = "gitlab-secrets-read"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          "arn:${var.aws_partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/gitlab/*",
          "arn:${var.aws_partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/ses/*",
        ]
      },
      {
        Sid    = "SecretsKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
        ]
        Resource = [
          data.terraform_remote_state.data.outputs.kms_key_arn,
        ]
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Policy: SSM Session Manager — Admin access without SSH (GL-016)
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "gitlab_ssm" {
  role       = aws_iam_role.gitlab.name
  policy_arn = "arn:${var.aws_partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Policy: CloudWatch Logs — Instance logging
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "gitlab_cloudwatch" {
  name = "gitlab-cloudwatch-logs"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:${var.aws_partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/gitlab/*"
      },
    ]
  })
}
