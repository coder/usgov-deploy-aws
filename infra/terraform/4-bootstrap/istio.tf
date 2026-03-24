################################################################################
# Istio Service Mesh
# coder4gov.com — Gov Demo Environment
#
# MESH-001: Install Istio CRDs (istio-base)
# MESH-002: Deploy istiod control plane with access logging
# MESH-003: Enforce STRICT mTLS PeerAuthentication per namespace
# MESH-004: holdApplicationUntilProxyStarts for init ordering
################################################################################

# ---------------------------------------------------------------------------
# MESH-001: Istio Base — CRDs and cluster-wide resources
# ---------------------------------------------------------------------------

resource "helm_release" "istio_base" {
  name             = "istio-base"
  namespace        = "istio-system"
  create_namespace = true
  wait             = true
  timeout          = 300

  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = var.istio_version

  set {
    name  = "defaultRevision"
    value = "default"
  }
}

# ---------------------------------------------------------------------------
# MESH-002 / MESH-004: istiod — control plane
# Access logging to stdout; holdApplicationUntilProxyStarts enabled.
# Scheduled on system nodes.
# ---------------------------------------------------------------------------

resource "helm_release" "istiod" {
  name             = "istiod"
  namespace        = "istio-system"
  create_namespace = true
  wait             = true
  timeout          = 600

  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = var.istio_version

  # --- Mesh-wide config ---
  values = [
    yamlencode({
      meshConfig = {
        accessLogFile = "/dev/stdout"
        defaultConfig = {
          holdApplicationUntilProxyStarts = true
        }
      }

      # Schedule on system nodes
      nodeSelector = {
        "scheduling.coder.com/pool" = "system"
      }
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [helm_release.istio_base]
}

# ---------------------------------------------------------------------------
# MESH-003: STRICT mTLS PeerAuthentication per application namespace
# Ensures all pod-to-pod traffic within the mesh uses mutual TLS.
# ---------------------------------------------------------------------------

locals {
  strict_mtls_namespaces = [
    "coder",
    "litellm",
    "keycloak",
    "istio-system",
  ]
}

resource "kubectl_manifest" "istio_peer_auth" {
  for_each = toset(local.strict_mtls_namespaces)

  yaml_body = yamlencode({
    apiVersion = "security.istio.io/v1"
    kind       = "PeerAuthentication"
    metadata = {
      name      = "strict-mtls"
      namespace = each.value
    }
    spec = {
      mtls = {
        mode = "STRICT"
      }
    }
  })

  depends_on = [helm_release.istiod]
}
