################################################################################
# Layer 3 – EKS Cluster & IRSA
# Project: coder4gov.com
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket            = "coder4gov-terraform-state"
    key               = "3-eks/terraform.tfstate"
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
# Kubernetes & Helm providers – configured after cluster creation
# ---------------------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
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
# Remote state – Layer 2 (Data)
# ---------------------------------------------------------------------------
data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket            = "coder4gov-terraform-state"
    key               = "2-data/terraform.tfstate"
    region            = var.aws_region
    encrypt           = true
    use_fips_endpoint = true
  }
}

# ---------------------------------------------------------------------------
# Convenience locals
# ---------------------------------------------------------------------------
locals {
  # Layer 1
  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr                   = data.terraform_remote_state.network.outputs.vpc_cidr
  public_subnet_ids          = data.terraform_remote_state.network.outputs.public_subnet_ids
  private_subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
  private_system_subnet_ids  = data.terraform_remote_state.network.outputs.private_system_subnet_ids
  private_workload_subnet_ids = data.terraform_remote_state.network.outputs.private_workload_subnet_ids
  route53_zone_id            = data.terraform_remote_state.network.outputs.route53_zone_id
  acm_wildcard_cert_arn      = data.terraform_remote_state.network.outputs.acm_wildcard_cert_arn

  # Layer 2
  kms_key_arn             = data.terraform_remote_state.data.outputs.kms_key_arn
  kms_key_id              = data.terraform_remote_state.data.outputs.kms_key_id
  rds_endpoint            = data.terraform_remote_state.data.outputs.rds_endpoint
  rds_port                = data.terraform_remote_state.data.outputs.rds_port
  rds_security_group_id   = data.terraform_remote_state.data.outputs.rds_security_group_id
  secret_arns             = data.terraform_remote_state.data.outputs.secret_arns

  # Derived
  cluster_name = "${var.project_name}-eks"
}

# Current account & partition
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
