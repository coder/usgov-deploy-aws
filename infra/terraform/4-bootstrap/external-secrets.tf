################################################################################
# External Secrets Operator (ESO)
# coder4gov.com — Gov Demo Environment
#
# Deploys ESO with an IRSA role for Secrets Manager access, then creates a
# ClusterSecretStore pointing at the project's AWS Secrets Manager.
################################################################################

# ---------------------------------------------------------------------------
# IAM policy — least-privilege Secrets Manager read access
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "eso" {
  # Scoped read access to project secrets.
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:BatchGetSecretValue",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["arn:${local.partition}:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/*"]
  }

  # ListSecrets does not support resource-level permissions.
  statement {
    sid       = "SecretsManagerList"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eso" {
  name_prefix = "${var.project_name}-eso-sm-"
  description = "Allows External Secrets Operator to read Secrets Manager secrets scoped to ${var.project_name}."
  policy      = data.aws_iam_policy_document.eso.json

  tags = {
    Component = "external-secrets"
  }
}

# ---------------------------------------------------------------------------
# IRSA role — bound to the external-secrets service account
# ---------------------------------------------------------------------------

module "eso_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${var.project_name}-eso-"

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    eso = aws_iam_policy.eso.arn
  }

  tags = {
    Component = "external-secrets"
  }
}

# ---------------------------------------------------------------------------
# Helm release — External Secrets Operator
# Scheduled on system nodes.
# ---------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_chart_version

  # --- Service account with IRSA annotation ---
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eso_irsa.iam_role_arn
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

  # --- Webhook on system nodes ---
  set {
    name  = "webhook.nodeSelector.scheduling\\.coder\\.com/pool"
    value = "system"
  }

  set {
    name  = "webhook.tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "webhook.tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "webhook.tolerations[0].effect"
    value = "NoSchedule"
  }

  # --- Cert controller on system nodes ---
  set {
    name  = "certController.nodeSelector.scheduling\\.coder\\.com/pool"
    value = "system"
  }

  set {
    name  = "certController.tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "certController.tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "certController.tolerations[0].effect"
    value = "NoSchedule"
  }
}

# ---------------------------------------------------------------------------
# ClusterSecretStore — AWS Secrets Manager via IRSA JWT auth
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secrets-manager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}
