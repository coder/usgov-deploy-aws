###############################################################################
# Layer 0 – State Backend Variables
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

variable "use_fips_endpoints" {
  description = "Whether to use FIPS-validated AWS API endpoints."
  type        = bool
  default     = true
}
