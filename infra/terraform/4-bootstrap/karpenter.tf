################################################################################
# Karpenter – Autoscaler for Coder Workspace Nodes
# coder4gov.com — Gov Demo Environment
#
# KARP-001: Karpenter IAM infrastructure (SQS, roles, instance profile)
# KARP-002: Karpenter controller Helm deployment
# KARP-003: EC2NodeClass with KMS-encrypted EBS and workload subnets
# KARP-004: NodePool with instance flexibility and consolidation
################################################################################

# ---------------------------------------------------------------------------
# KARP-001: AWS infrastructure — SQS queue, IAM roles, instance profile
# Uses the official EKS module's Karpenter sub-module.
# ---------------------------------------------------------------------------

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = local.cluster_name

  # IAM role for the Karpenter controller pod (IRSA)
  create_iam_role          = true
  iam_role_use_name_prefix = true

  # IAM role for nodes launched by Karpenter
  create_node_iam_role          = true
  node_iam_role_use_name_prefix = true

  # Spot termination handling via SQS
  enable_spot_termination = true

  # We use IRSA, not EKS Pod Identity
  create_pod_identity_association = false

  # Additional policies for launched nodes
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Component = "karpenter"
  }
}

# ---------------------------------------------------------------------------
# KARP-002: Karpenter controller Helm release
# Runs on system nodes via nodeSelector + tolerations.
# ---------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version

  # --- IRSA annotation ---
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.iam_role_arn
  }

  # --- Cluster settings ---
  set {
    name  = "settings.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = local.cluster_endpoint
  }

  set {
    name  = "settings.interruptionQueue"
    value = module.karpenter.queue_name
  }

  # --- Schedule on system nodes (KARP-002) ---
  set {
    name  = "nodeSelector.scheduling\\.coder\\.com/pool"
    value = "system"
  }

  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [module.karpenter]
}

# ---------------------------------------------------------------------------
# KARP-003: EC2NodeClass "coder"
# Defines AMI, subnets, security groups, and KMS-encrypted EBS for
# workspace nodes launched by Karpenter.
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "karpenter_ec2nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "coder"
    }
    spec = {
      role = module.karpenter.node_iam_role_name

      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.cluster_name
            "network/type"           = "workload"
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "200Gi"
            volumeType          = "gp3"
            encrypted           = true
            kmsKeyId            = local.kms_key_arn
            deleteOnTermination = true
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

# ---------------------------------------------------------------------------
# KARP-004: NodePool "workspaces"
# Flexible instance types, spot + on-demand, with consolidation.
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "karpenter_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "workspaces"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "scheduling.coder.com/pool" = "workspaces"
          }
        }
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.workspace_instance_types
            },
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              values   = var.workspace_azs
            },
          ]

          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "coder"
          }

          expireAfter = "720h"
        }
      }

      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }

      limits = {
        cpu    = "200"
        memory = "800Gi"
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_ec2nodeclass]
}
