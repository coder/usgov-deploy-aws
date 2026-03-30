################################################################################
# Variables – Layer 2 Data
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
# RDS
# ---------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.m7g.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GiB for the RDS instance."
  type        = number
  default     = 50
}

variable "db_max_allocated_storage" {
  description = "Maximum storage in GiB for RDS auto-scaling."
  type        = number
  default     = 200
}

variable "db_master_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "coder4gov_admin"
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------------------
# CI/CD
# ---------------------------------------------------------------------------
variable "github_repo" {
  description = "GitHub repo (org/name) allowed to assume the CI role via OIDC."
  type        = string
  default     = "coder/usgov-deploy-aws"
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
    Layer       = "2-data"
    Environment = "production"
  }
}
