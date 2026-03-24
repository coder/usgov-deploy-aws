###############################################################################
# Layer 5 – AWS Provider & Backend
# coder4gov.com — Gov Demo Environment
#
# FIPS endpoints are enabled by default (INFRA-003).
# State is stored in the S3 bucket created by Layer 0.
#
# Remote state references:
#   1-network  → VPC, subnets, Route 53 zone, ACM cert, KMS keys
#   2-data     → S3 buckets (backups, artifacts), SES, ECR, Secrets Manager
#   3-eks      → (reserved for future cross-references)
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket            = "coder4gov-terraform-state"
    key               = "5-gitlab/terraform.tfstate"
    region            = "us-west-2"
    encrypt           = true
    dynamodb_table    = "coder4gov-terraform-lock"
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
      Layer       = "5-gitlab"
      Environment = "gov-demo"
    }
  }
}

# ---------------------------------------------------------------------------
# Remote State — Layer 1 (Network)
# VPC ID, subnet IDs, Route 53 zone, ACM wildcard cert, KMS keys
# ---------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "coder4gov-terraform-state"
    key    = "1-network/terraform.tfstate"
    region = var.aws_region
  }
}

# ---------------------------------------------------------------------------
# Remote State — Layer 2 (Data)
# S3 buckets, SES config, ECR repos, Secrets Manager, KMS keys
# ---------------------------------------------------------------------------

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = "coder4gov-terraform-state"
    key    = "2-data/terraform.tfstate"
    region = var.aws_region
  }
}

# ---------------------------------------------------------------------------
# Remote State — Layer 3 (EKS)
# Cluster endpoint, security groups (reserved for future cross-references)
# ---------------------------------------------------------------------------

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = "coder4gov-terraform-state"
    key    = "3-eks/terraform.tfstate"
    region = var.aws_region
  }
}
