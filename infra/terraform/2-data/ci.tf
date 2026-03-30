################################################################################
# GitHub Actions IAM Role (CI/CD for ECR image pushes)
#
# Creates:
#   - IAM role assumable only by this repo's GitHub Actions workflows
#   - Inline policy granting ECR push/pull to project repos only
#
# PREREQUISITE: The GitHub Actions OIDC identity provider must exist in
# the AWS account. This is a one-time, account-level setup — run once:
#
#   aws iam create-open-id-connect-provider \
#     --url https://token.actions.githubusercontent.com \
#     --client-id-list sts.amazonaws.com \
#     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
#
# The role ARN and ECR registry URL should be stored as GitHub repo secrets:
#   AWS_ROLE_ARN  = aws_iam_role.github_actions.arn
#   ECR_REGISTRY  = <account_id>.dkr.ecr.<region>.amazonaws.com
################################################################################

# ---------------------------------------------------------------------------
# Look up the existing OIDC provider. Fails if the prerequisite above
# hasn't been run — that's intentional (clear error > silent misconfiguration).
# ---------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
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
          Federated = data.aws_iam_openid_connect_provider.github.arn
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
