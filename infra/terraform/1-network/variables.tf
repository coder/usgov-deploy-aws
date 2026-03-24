###############################################################################
# Layer 1 – Network Variables
# coder4gov.com — Gov Demo Environment
###############################################################################

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

variable "domain_name" {
  description = "Base domain name. Route 53 zone and ACM certs are created for this domain."
  type        = string
  default     = "coder4gov.com"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use. Must be >= 2 (INFRA-008)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "At least 2 AZs are required per INFRA-008."
  }
}

variable "use_fips_endpoints" {
  description = "Whether to use FIPS-validated AWS API endpoints."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
