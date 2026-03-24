###############################################################################
# Layer 0 – AWS Provider
# coder4gov.com — Gov Demo Environment
#
# FIPS endpoints are enabled by default (INFRA-003).
# Override use_fips_endpoints = false only for local testing.
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  use_fips_endpoint = var.use_fips_endpoints

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Layer       = "0-state"
      Environment = "gov-demo"
    }
  }
}
