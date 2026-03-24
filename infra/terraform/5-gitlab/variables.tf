###############################################################################
# Layer 5 – GitLab CE Variables
# coder4gov.com — Gov Demo Environment
###############################################################################

# ---------------------------------------------------------------------------
# Common
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
  description = "Base domain name for the environment."
  type        = string
  default     = "coder4gov.com"
}

# ---------------------------------------------------------------------------
# GitLab EC2
# ---------------------------------------------------------------------------

variable "gitlab_instance_type" {
  description = "EC2 instance type for GitLab CE. m7a.2xlarge = 8 vCPU / 32 GiB AMD (GL-001)."
  type        = string
  default     = "m7a.2xlarge"
}

variable "gitlab_volume_size" {
  description = "Root EBS volume size in GiB for the GitLab EC2 instance."
  type        = number
  default     = 100
}

variable "gitlab_data_volume_size" {
  description = "Data EBS volume size in GiB mounted at /var/opt/gitlab for git repos."
  type        = number
  default     = 200
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access during initial setup only. Set to empty string to disable."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed SSH access during initial setup. Empty after setup (GL-016)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
