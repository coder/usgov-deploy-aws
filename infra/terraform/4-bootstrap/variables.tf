################################################################################
# Variables – Layer 4 Bootstrap / Platform Services
# coder4gov.com — Gov Demo Environment
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
# Istio (MESH-001 through MESH-008)
# ---------------------------------------------------------------------------

variable "istio_version" {
  description = "Helm chart version for Istio (base + istiod)."
  type        = string
  default     = "1.24.0"
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

# ---------------------------------------------------------------------------
# WAF (SEC-010 through SEC-013)
# ---------------------------------------------------------------------------

variable "allowed_admin_cidrs" {
  description = "CIDR blocks allowed to access Keycloak /admin paths. Empty list disables the rule."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# FluxCD (FLUX-001 through FLUX-007)
# ---------------------------------------------------------------------------

variable "flux_bootstrap_enabled" {
  description = "Enable FluxCD bootstrap. Set to false on first apply when GitLab is not yet provisioned."
  type        = bool
  default     = false
}

variable "flux_git_url" {
  description = "Git repository URL for FluxCD bootstrap (SSH or HTTPS)."
  type        = string
  default     = ""
}

variable "flux_git_branch" {
  description = "Git branch for FluxCD bootstrap."
  type        = string
  default     = "main"
}

variable "flux_git_token" {
  description = "Git personal-access or deploy token for HTTPS-based FluxCD bootstrap. Leave empty for SSH."
  type        = string
  default     = ""
  sensitive   = true
}
