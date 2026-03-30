################################################################################
# Variables – Layer 3 EKS
################################################################################

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project slug used in naming and tagging."
  type        = string
  default     = "coder4gov"
}

variable "use_fips_endpoints" {
  description = "Whether to use FIPS-validated endpoints."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (EKS-001)."
  type        = string
  default     = "1.33"
}

variable "system_node_instance_types" {
  description = "Instance types for the system managed node group (EKS-003)."
  type        = list(string)
  default     = ["m7a.xlarge"]
}

variable "system_node_min_size" {
  description = "Minimum number of system nodes."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum number of system nodes."
  type        = number
  default     = 4
}

variable "system_node_desired_size" {
  description = "Desired number of system nodes."
  type        = number
  default     = 2
}

variable "system_node_disk_size" {
  description = "Root disk size (GiB) for system nodes."
  type        = number
  default     = 100
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------
variable "tags" {
  description = "Default tags applied to all resources."
  type        = map(string)
  default = {
    Project     = "coder4gov"
    ManagedBy   = "terraform"
    Layer       = "3-eks"
    Environment = "production"
  }
}
