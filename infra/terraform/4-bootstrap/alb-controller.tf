################################################################################
# AWS Load Balancer Controller
# coder4gov.com — Gov Demo Environment
#
# Provisions an IRSA role with the official LB controller policy and deploys
# the controller Helm chart into the cluster.
################################################################################

# ---------------------------------------------------------------------------
# IRSA role — grants the controller permissions to manage ALB/NLB resources
# ---------------------------------------------------------------------------

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${var.project_name}-alb-ctrl-"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["lb-ctrl:aws-load-balancer-controller"]
    }
  }

  tags = {
    Component = "alb-controller"
  }
}

# ---------------------------------------------------------------------------
# Helm release — AWS Load Balancer Controller
# Scheduled on system nodes.
# ---------------------------------------------------------------------------

resource "helm_release" "alb_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = "lb-ctrl"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  # --- Core settings ---
  set {
    name  = "clusterName"
    value = local.cluster_name
  }

  set {
    name  = "vpcId"
    value = local.vpc_id
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  # --- Service account with IRSA annotation ---
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa.iam_role_arn
  }

  # --- Schedule on system nodes ---
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
}
