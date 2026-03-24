################################################################################
# FluxCD Bootstrap
# coder4gov.com — Gov Demo Environment
#
# FLUX-001: FluxCD source controller + Kustomize controller
# FLUX-002: Git repository connection (GitLab)
# FLUX-003: Cluster path = clusters/gov-demo
# FLUX-004: Branch tracking (main)
# FLUX-005: Reconciliation on push (webhook) and interval
# FLUX-006: Gated behind flux_bootstrap_enabled to handle chicken-and-egg
#           with GitLab provisioning (Layer 5)
# FLUX-007: Provides status output for downstream automation
#
# On first apply flux_bootstrap_enabled = false (default). After GitLab is
# provisioned in Layer 5, set the variable to true and re-apply.
################################################################################

# ---------------------------------------------------------------------------
# FLUX-006: Placeholder when FluxCD is disabled (first apply)
# ---------------------------------------------------------------------------

resource "null_resource" "flux_disabled_notice" {
  count = var.flux_bootstrap_enabled ? 0 : 1

  provisioner "local-exec" {
    command = <<-EOT
      echo "============================================================"
      echo " FluxCD bootstrap is DISABLED (flux_bootstrap_enabled=false)"
      echo ""
      echo " This is expected on the first apply before GitLab (Layer 5)"
      echo " has been provisioned. Once GitLab is running:"
      echo ""
      echo "   1. Set flux_bootstrap_enabled = true"
      echo "   2. Set flux_git_url to the GitLab repo SSH/HTTPS URL"
      echo "   3. Re-run: terraform apply -var flux_bootstrap_enabled=true"
      echo "============================================================"
    EOT
  }

  triggers = {
    always = timestamp()
  }
}

# ---------------------------------------------------------------------------
# FLUX-001 through FLUX-005: FluxCD bootstrap via Helm
#
# When the official fluxcd Terraform provider is not available in the
# environment, we use the flux2 Helm chart which bundles all controllers
# (source, kustomize, helm, notification) in a single release, then
# create a GitRepository + Kustomization via kubectl_manifest.
# ---------------------------------------------------------------------------

resource "helm_release" "flux" {
  count = var.flux_bootstrap_enabled ? 1 : 0

  name             = "flux"
  namespace        = "flux-system"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2"

  # Schedule controllers on system nodes
  values = [
    yamlencode({
      sourceController = {
        nodeSelector = { "scheduling.coder.com/pool" = "system" }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }
      kustomizeController = {
        nodeSelector = { "scheduling.coder.com/pool" = "system" }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }
      helmController = {
        nodeSelector = { "scheduling.coder.com/pool" = "system" }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }
      notificationController = {
        nodeSelector = { "scheduling.coder.com/pool" = "system" }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }
    })
  ]
}

# ---------------------------------------------------------------------------
# FLUX-002 / FLUX-003: Kubernetes Secret for Git credentials (HTTPS token)
# Only created when a token is provided.
# ---------------------------------------------------------------------------

resource "kubernetes_secret" "flux_git_auth" {
  count = var.flux_bootstrap_enabled && var.flux_git_token != "" ? 1 : 0

  metadata {
    name      = "flux-git-auth"
    namespace = "flux-system"
  }

  data = {
    username = "git"
    password = var.flux_git_token
  }

  type = "Opaque"

  depends_on = [helm_release.flux]
}

# ---------------------------------------------------------------------------
# FLUX-002: GitRepository source pointing at the platform repo
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "flux_git_repository" {
  count = var.flux_bootstrap_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = "platform"
      namespace = "flux-system"
    }
    spec = {
      interval = "5m"
      url      = var.flux_git_url
      ref = {
        branch = var.flux_git_branch
      }
      secretRef = var.flux_git_token != "" ? {
        name = "flux-git-auth"
      } : null
    }
  })

  depends_on = [helm_release.flux]
}

# ---------------------------------------------------------------------------
# FLUX-003 / FLUX-004: Kustomization — reconcile clusters/gov-demo path
# ---------------------------------------------------------------------------

resource "kubectl_manifest" "flux_kustomization" {
  count = var.flux_bootstrap_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "platform"
      namespace = "flux-system"
    }
    spec = {
      interval = "10m"
      path     = "./clusters/gov-demo"
      prune    = true
      sourceRef = {
        kind = "GitRepository"
        name = "platform"
      }
      timeout = "5m"
    }
  })

  depends_on = [kubectl_manifest.flux_git_repository]
}
