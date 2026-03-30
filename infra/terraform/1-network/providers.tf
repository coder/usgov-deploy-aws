###############################################################################
# Layer 1 – AWS Provider & Backend
# coder4gov.com — Gov Demo Environment
#
# FIPS endpoints are enabled by default (INFRA-003).
# State is stored in the S3 bucket created by Layer 0.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket            = "coder4gov-terraform-state"
    key               = "1-network/terraform.tfstate"
    region            = "us-west-2"
    encrypt           = true
    use_lockfile      = true
    use_fips_endpoint = true
  }
}

provider "aws" {
  region = var.aws_region

  use_fips_endpoint = var.use_fips_endpoints

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Layer       = "1-network"
      Environment = "gov-demo"
    }
  }
}
