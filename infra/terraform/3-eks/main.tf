################################################################################
# Layer 3 – EKS Cluster (EKS-001 → EKS-009)
# coder4gov.com — Gov Demo Environment
################################################################################

locals {
  # Karpenter security-group discovery tag (EKS-006, KARP-001)
  karpenter_discovery_tag = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  system_node_labels = {
    "scheduling.coder.com/pool" = "system"
  }

  system_node_taints = {
    key    = "CriticalAddonsOnly"
    effect = "NO_SCHEDULE"
  }
}

# ---------------------------------------------------------------------------
# EKS Cluster (EKS-001, EKS-002, EKS-004, EKS-005)
# ---------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = local.vpc_id
  subnet_ids = concat(local.private_system_subnet_ids, local.private_workload_subnet_ids)

  # API server access (EKS-002)
  endpoint_public_access  = true
  endpoint_private_access = true

  # IRSA (EKS-005)
  enable_irsa = true

  # Admin access for the cluster creator
  enable_cluster_creator_admin_permissions = true

  # Encryption at rest with KMS (EKS-004)
  encryption_config = {
    provider_key_arn = local.kms_key_arn
    resources        = ["secrets"]
  }

  # Security groups — tag node SG for Karpenter discovery (KARP-001)
  create_security_group      = true
  create_node_security_group = true
  node_security_group_tags   = local.karpenter_discovery_tag

  # ---------------------------------------------------------------------------
  # Managed add-ons (EKS-007)
  # ---------------------------------------------------------------------------
  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        nodeAgent = {
          enablePolicyEventLogs = "true"
        }
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          WARM_IP_TARGET           = "0"
        }
      })
    }

    coredns = {
      most_recent    = true
      before_compute = true
    }

    kube-proxy = {
      most_recent    = true
      before_compute = true
    }

    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  # ---------------------------------------------------------------------------
  # System managed node group (EKS-003)
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    system = {
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_min_size
      max_size     = var.system_node_max_size
      desired_size = var.system_node_desired_size

      disk_size = var.system_node_disk_size

      # Place system nodes only in system subnets
      subnet_ids = local.private_system_subnet_ids

      labels = local.system_node_labels

      taints = {
        critical = local.system_node_taints
      }

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  tags = {}
}

# ---------------------------------------------------------------------------
# EKS → RDS connectivity (allow workers to reach Postgres)
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "eks_to_rds" {
  description              = "Allow EKS worker nodes to connect to RDS (port 5432)"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = local.rds_security_group_id
}
