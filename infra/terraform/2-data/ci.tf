################################################################################
# GitHub Actions OIDC → AWS IAM (CI/CD for ECR image pushes)
#
# Creates:
#   - OIDC identity provider for GitHub Actions (if not already present)
#   - IAM role assumable only by this repo's GitHub Actions workflows
#   - Inline policy granting ECR push/pull to project repos only
#
# The role ARN and ECR registry URL should be stored as GitHub repo secrets:
#   AWS_ROLE_ARN  = aws_iam_role.github_actions.arn
#   ECR_REGISTRY  = <account_id>.dkr.ecr.<region>.amazonaws.com
################################################################################

# ---------------------------------------------------------------------------
# OIDC Identity Provider — trust GitHub Actions JWTs
# One per AWS account. If you already have this from another repo, import it:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# ---------------------------------------------------------------------------
# IAM Role — assumable only by workflows in this specific GitHub repo
# ---------------------------------------------------------------------------

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-ci"
  }
}

# ---------------------------------------------------------------------------
# ECR push/pull permissions — scoped to this project's repos only
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
        ]
        Resource = [
          for repo in aws_ecr_repository.repos :
          repo.arn
        ]
      },
    ]
  })
}
