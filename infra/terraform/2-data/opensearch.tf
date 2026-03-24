################################################################################
# OpenSearch Serverless — SIEM / Log Analytics (LOG-001 → LOG-007)
#
# Ingests: CloudTrail, VPC Flow Logs, Coder audit, Keycloak auth events
# via CloudWatch Logs subscription filters → OpenSearch Serverless collection.
################################################################################

# ---------------------------------------------------------------------------
# LOG-001: Encryption policy (required before collection creation)
# ---------------------------------------------------------------------------
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.project_name}-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.project_name}-siem"]
      }
    ]
    AWSOwnedKey = false
    KmsARN      = aws_kms_key.main.arn
  })
}

# ---------------------------------------------------------------------------
# LOG-002: Network policy — public dashboard access (VPC endpoint optional)
# ---------------------------------------------------------------------------
resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.project_name}-network"
  type = "network"

  policy = jsonencode([
    {
      Description = "Public access to ${var.project_name} SIEM collection"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.project_name}-siem"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${var.project_name}-siem"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

# ---------------------------------------------------------------------------
# LOG-003: OpenSearch Serverless collection (TIMESERIES type for logs)
# ---------------------------------------------------------------------------
resource "aws_opensearchserverless_collection" "siem" {
  name        = "${var.project_name}-siem"
  description = "SIEM collection for ${var.project_name} — CloudTrail, VPC Flow Logs, Coder audit, Keycloak auth"
  type        = "TIMESERIES"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = {
    Name      = "${var.project_name}-siem"
    Component = "logging"
  }
}

# ---------------------------------------------------------------------------
# LOG-004: Data access policy — allow CloudWatch and admin roles to write/read
# ---------------------------------------------------------------------------
resource "aws_opensearchserverless_access_policy" "siem" {
  name = "${var.project_name}-siem-access"
  type = "data"

  policy = jsonencode([
    {
      Description = "Admin and CloudWatch write access to SIEM collection"
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${var.project_name}-siem/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        },
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.project_name}-siem"]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DescribeCollectionItems",
            "aoss:UpdateCollectionItems",
          ]
        }
      ]
      Principal = [
        data.aws_caller_identity.current.arn,
        aws_iam_role.opensearch_ingestion.arn,
      ]
    }
  ])
}

# ---------------------------------------------------------------------------
# LOG-005: IAM role for CloudWatch → OpenSearch ingestion
# ---------------------------------------------------------------------------
resource "aws_iam_role" "opensearch_ingestion" {
  name = "${var.project_name}-opensearch-ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "opensearch_ingestion" {
  name = "opensearch-write"
  role = aws_iam_role.opensearch_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OpenSearchWrite"
        Effect = "Allow"
        Action = [
          "aoss:BatchGetCollection",
          "aoss:APIAccessAll",
        ]
        Resource = aws_opensearchserverless_collection.siem.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# LOG-006: CloudWatch subscription filters → OpenSearch
# These forward logs from existing CloudWatch log groups.
# ---------------------------------------------------------------------------

# CloudTrail log group (created in Layer 1 or by AWS)
variable "cloudtrail_log_group_name" {
  description = "CloudWatch Log Group for CloudTrail events."
  type        = string
  default     = "/aws/cloudtrail/coder4gov"
}

resource "aws_cloudwatch_log_subscription_filter" "cloudtrail" {
  name            = "${var.project_name}-cloudtrail-to-opensearch"
  log_group_name  = var.cloudtrail_log_group_name
  filter_pattern  = ""
  destination_arn = aws_opensearchserverless_collection.siem.arn
  role_arn        = aws_iam_role.opensearch_ingestion.arn

  depends_on = [aws_opensearchserverless_access_policy.siem]
}

# VPC Flow Logs log group (created in Layer 1)
resource "aws_cloudwatch_log_subscription_filter" "vpc_flow_logs" {
  name            = "${var.project_name}-flowlogs-to-opensearch"
  log_group_name  = "/aws/vpc/flowlogs/${var.project_name}"
  filter_pattern  = ""
  destination_arn = aws_opensearchserverless_collection.siem.arn
  role_arn        = aws_iam_role.opensearch_ingestion.arn

  depends_on = [aws_opensearchserverless_access_policy.siem]
}
