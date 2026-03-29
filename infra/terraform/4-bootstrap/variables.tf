################################################################################
# Variables – Layer 4 Bootstrap / Platform Services
# coder4gov.com — Coder Reference Architecture
################################################################################

# ---------------------------------------------------------------------------
# Standard – shared across all layers
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources. Override to us-gov-west-1 for GovCloud."
  type        = string
  default     = "us-west-2"
}

variable "aws_partition" {
  description = "AWS partition. Override to aws-us-gov for GovCloud."
  type        = string
  default     = "aws"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "coder4gov"
}

variable "use_fips_endpoints" {
  description = "Whether to use FIPS-validated AWS API endpoints (INFRA-003)."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Primary domain name."
  type        = string
  default     = "coder4gov.com"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Karpenter (KARP-001 through KARP-008)
# ---------------------------------------------------------------------------

variable "karpenter_chart_version" {
  description = "Helm chart version for the Karpenter controller."
  type        = string
  default     = "1.9.0"
}

variable "workspace_instance_types" {
  description = "Allowed EC2 instance types for the workspace NodePool."
  type        = list(string)
  default = [
    "m7a.xlarge",
    "m7a.2xlarge",
    "m7a.4xlarge",
    "m7i.xlarge",
    "m7i.2xlarge",
    "m7i.4xlarge",
  ]
}

variable "workspace_azs" {
  description = "Availability zones for workspace nodes. Must match the target region (e.g. us-gov-west-1a/b for GovCloud)."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
# ---------------------------------------------------------------------------

variable "alb_controller_chart_version" {
  description = "Helm chart version for the AWS Load Balancer Controller."
  type        = string
  default     = "1.12.0"
}

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------

variable "eso_chart_version" {
  description = "Helm chart version for External Secrets Operator."
  type        = string
  default     = "0.14.0"
}
