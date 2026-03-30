################################################################################
# Layer 4 – Bootstrap / Platform Services
# coder4gov.com — Coder Reference Architecture
#
# Deploys Karpenter, ALB Controller, and External Secrets Operator.
#
# FIPS endpoints are enabled by default (INFRA-003).
# State is stored in the S3 bucket created by Layer 0.
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket            = "coder4gov-terraform-state"
    key               = "4-bootstrap/terraform.tfstate"
    region            = "us-west-2"
    encrypt           = true
    dynamodb_table    = "coder4gov-terraform-lock"
    use_fips_endpoint = true
  }
}

# ---------------------------------------------------------------------------
# AWS Provider
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  use_fips_endpoint = var.use_fips_endpoints

  default_tags {
    tags = var.tags
  }
}

# ---------------------------------------------------------------------------
# Kubernetes Provider — configured from EKS Layer 3 remote state
# ---------------------------------------------------------------------------

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
  }
}

# ---------------------------------------------------------------------------
# Helm Provider — same auth as Kubernetes
# ---------------------------------------------------------------------------

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
    }
  }
}

# ---------------------------------------------------------------------------
# kubectl Provider — same auth as Kubernetes
# ---------------------------------------------------------------------------

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
  }
}

# ---------------------------------------------------------------------------
# Remote State — Layer 1 (Network)
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
# Remote State — Layer 2 (Data)
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
# Remote State — Layer 3 (EKS)
# ---------------------------------------------------------------------------

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket            = "coder4gov-terraform-state"
    key               = "3-eks/terraform.tfstate"
    region            = var.aws_region
    encrypt           = true
    use_fips_endpoint = true
  }
}

# ---------------------------------------------------------------------------
# Current account & partition
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Convenience Locals — aggregated from remote state outputs
# ---------------------------------------------------------------------------

locals {
  # Layer 1 — Network
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  # Layer 2 — Data
  kms_key_arn = data.terraform_remote_state.data.outputs.kms_key_arn

  # Layer 3 — EKS
  cluster_name      = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_endpoint  = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_data   = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.cluster_oidc_provider_arn

  # Derived
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}
