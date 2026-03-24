################################################################################
# IRSA Roles – Layer 3 (EKS-005)
# One role per workload, least-privilege IAM policies.
#
# NOTE: ALB Controller and External Secrets IRSA are in Layer 4, co-located
# with their Helm charts. Only workloads consumed by FluxCD HelmReleases
# (which need the ARN injected as a value) live here.
################################################################################

# ============================================================================
# 1. EBS CSI Driver (EKS-007)
# ============================================================================
module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                     = "${var.project_name}-ebs-csi"
  attach_ebs_csi_policy         = true
  ebs_csi_kms_cmk_ids           = [local.kms_key_arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ============================================================================
# 2. Loki – S3 storage (OBS-003)
# ============================================================================
resource "aws_iam_policy" "loki" {
  name        = "${var.project_name}-loki"
  description = "Allow Loki to read/write logs in S3."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LokiS3"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          local.s3_loki_bucket_arn,
          "${local.s3_loki_bucket_arn}/*",
        ]
      },
    ]
  })
}

module "irsa_loki" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-loki"

  role_policy_arns = {
    loki = aws_iam_policy.loki.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:loki"]
    }
  }
}

# ============================================================================
# 3. LiteLLM – Bedrock access (AI-001 → AI-010)
# ============================================================================
resource "aws_iam_policy" "litellm_bedrock" {
  name        = "${var.project_name}-litellm-bedrock"
  description = "Allow LiteLLM to invoke Bedrock foundation models."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"
      },
      {
        Sid    = "BedrockCrossRegionInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      },
    ]
  })
}

module "irsa_litellm" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-litellm"

  role_policy_arns = {
    bedrock = aws_iam_policy.litellm_bedrock.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["litellm:litellm"]
    }
  }
}

# ============================================================================
# 4. Coder Provisioner (PROV-001 → PROV-005)
# ============================================================================
resource "aws_iam_policy" "coder_provisioner" {
  name        = "${var.project_name}-coder-provisioner"
  description = "Allow Coder provisioner to manage EC2 instances and EKS resources."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:GetLaunchTemplateData",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Write"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*"
      },
      {
        Sid    = "EKSRead"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "*"
      },
    ]
  })
}

module "irsa_coder_provisioner" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.project_name}-coder-provisioner"

  role_policy_arns = {
    coder_provisioner = aws_iam_policy.coder_provisioner.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["coder:coder-provisioner"]
    }
  }
}
