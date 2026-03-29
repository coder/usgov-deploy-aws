################################################################################
# Layer 2 – Data (RDS, KMS, ECR, Secrets Manager)
# Project: coder4gov.com
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket            = "coder4gov-terraform-state"
    key               = "2-data/terraform.tfstate"
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
    tags = var.tags
  }
}

# ---------------------------------------------------------------------------
# Remote state – Layer 1 (Network)
# ---------------------------------------------------------------------------
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket            = "coder4gov-terraform-state"
    key               = "1-network/terraform.tfstate"
    region            = var.aws_region
    encrypt           = true
    use_fips_endpoint = true
  }
}

# ---------------------------------------------------------------------------
# Convenience locals from Layer 1 outputs
# ---------------------------------------------------------------------------
locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.network.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  route53_zone_id    = data.terraform_remote_state.network.outputs.route53_zone_id
}

# Current account & caller identity
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
