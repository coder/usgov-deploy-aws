#!/usr/bin/env bash
# =============================================================================
# inject-outputs.sh — Patch FluxCD HelmRelease manifests with Terraform outputs
# =============================================================================
# Reads Terraform output values from infrastructure layers and patches the
# corresponding empty ("") placeholder fields in FluxCD HelmRelease YAML files.
#
# Layers consumed:
#   1-network  → acm_wildcard_cert_arn
#   3-eks      → irsa_role_arns  (keys: coder_server, coder_provisioner)
#
# Prerequisites:
#   - Terraform layers 1-network and 3-eks must be applied
#   - yq v4+ and jq must be installed
#
# Usage:
#   ./scripts/inject-outputs.sh              # Patch YAML files in place
#   ./scripts/inject-outputs.sh --dry-run    # Print changes without writing
# =============================================================================
set -euo pipefail

# Fast-path: print help without requiring dependencies.
for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      # Print the header comment block (lines 3–18) as usage text.
      awk 'NR>=3 && NR<=18 { sub(/^# ?/, ""); print }' "$0"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
if ! command -v yq &>/dev/null; then
  echo "ERROR: yq (v4+) is required but not found." >&2
  echo "" >&2
  echo "Install instructions:" >&2
  echo "  brew install yq                                  # macOS (Homebrew)" >&2
  echo "  go install github.com/mikefarah/yq/v4@latest     # Go" >&2
  echo "  snap install yq                                  # Linux (snap)" >&2
  echo "  wget https://github.com/mikefarah/yq/releases    # Binary release" >&2
  exit 1
fi

# Verify yq is v4+ (mikefarah/yq).
yq_version="$(yq --version 2>&1)"
if ! echo "${yq_version}" | grep -qE 'version v?4'; then
  echo "ERROR: yq v4+ is required." >&2
  echo "       Detected: ${yq_version}" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found." >&2
  echo "" >&2
  echo "Install instructions:" >&2
  echo "  brew install jq          # macOS (Homebrew)" >&2
  echo "  apt-get install jq       # Debian / Ubuntu" >&2
  echo "  yum install jq           # RHEL / CentOS" >&2
  exit 1
fi

if ! command -v terraform &>/dev/null; then
  echo "ERROR: terraform is required but not found." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
DRY_RUN=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) ;; # Already handled above.
    *)
      echo "Unknown flag: ${arg}" >&2
      echo "Usage: $0 [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SERVER_HR="${REPO_ROOT}/clusters/gov-demo/apps/coder-server/helmrelease.yaml"
PROVISIONER_HR="${REPO_ROOT}/clusters/gov-demo/apps/coder-provisioner/helmrelease.yaml"

for f in "${SERVER_HR}" "${PROVISIONER_HR}"; do
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: HelmRelease not found: ${f}" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Read Terraform outputs (one call per layer)
# ---------------------------------------------------------------------------
echo "==> Reading Terraform outputs ..."

echo "    Layer 1-network ..."
NETWORK_JSON="$(terraform -chdir="${REPO_ROOT}/infra/terraform/1-network" \
  output -json 2>/dev/null)" || {
  echo "ERROR: Failed to read outputs from 1-network." >&2
  echo "       Has the layer been initialized and applied?" >&2
  exit 1
}

echo "    Layer 3-eks ..."
EKS_JSON="$(terraform -chdir="${REPO_ROOT}/infra/terraform/3-eks" \
  output -json 2>/dev/null)" || {
  echo "ERROR: Failed to read outputs from 3-eks." >&2
  echo "       Has the layer been initialized and applied?" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Extract values from JSON
# ---------------------------------------------------------------------------
ACM_CERT_ARN="$(echo "${NETWORK_JSON}" \
  | jq -r '.acm_wildcard_cert_arn.value // empty')"

CODER_SERVER_IRSA="$(echo "${EKS_JSON}" \
  | jq -r '.irsa_role_arns.value.coder_server // empty')"

CODER_PROVISIONER_IRSA="$(echo "${EKS_JSON}" \
  | jq -r '.irsa_role_arns.value.coder_provisioner // empty')"

echo ""
echo "    acm_wildcard_cert_arn ............ ${ACM_CERT_ARN:-(not available)}"
echo "    coder_server_irsa_role_arn ....... ${CODER_SERVER_IRSA:-(not available)}"
echo "    coder_provisioner_irsa_role_arn .. ${CODER_PROVISIONER_IRSA:-(not available)}"
echo ""

# ---------------------------------------------------------------------------
# Patch helper
# ---------------------------------------------------------------------------
PATCHED=0
SKIPPED=0
MISSING=0

# patch_yaml FILE YQ_PATH NEW_VALUE LABEL
#   - If NEW_VALUE is empty, prints a warning and increments MISSING.
#   - If the YAML field already holds a non-empty value, skips it.
#   - Otherwise, sets the field (or prints what would happen in dry-run).
patch_yaml() {
  local file="$1" yq_path="$2" new_value="$3" label="$4"

  # Value not available from Terraform.
  if [[ -z "${new_value}" ]]; then
    echo "  MISS  ${label}"
    echo "        Terraform output not available — cannot patch."
    ((MISSING++)) || true
    return
  fi

  # Read current value from the YAML file.
  local current
  current="$(yq eval "${yq_path}" "${file}")"

  # Treat empty string, null, and literal '""' as unset.
  if [[ -n "${current}" && "${current}" != "null" && "${current}" != '""' ]]; then
    echo "  KEEP  ${label}"
    echo "        Already set: ${current}"
    ((SKIPPED++)) || true
    return
  fi

  if "${DRY_RUN}"; then
    echo "  WOULD SET  ${label}"
    echo "             → ${new_value}"
  else
    # Use strenv() to safely inject the value without shell escaping
    # issues (ARNs contain colons and slashes).
    NEW_VALUE="${new_value}" yq eval \
      "${yq_path} = strenv(NEW_VALUE)" -i "${file}"
    echo "  SET   ${label}"
    echo "        → ${new_value}"
  fi
  ((PATCHED++)) || true
}

# ---------------------------------------------------------------------------
# Apply patches
# ---------------------------------------------------------------------------
echo "==> Patching HelmRelease manifests ..."
echo ""

echo "--- coder-server/helmrelease.yaml ---"

patch_yaml \
  "${SERVER_HR}" \
  '.spec.values.coder.serviceAccount.annotations."eks.amazonaws.com/role-arn"' \
  "${CODER_SERVER_IRSA}" \
  "coder server IRSA role ARN"

patch_yaml \
  "${SERVER_HR}" \
  '.spec.values.coder.ingress.annotations."alb.ingress.kubernetes.io/certificate-arn"' \
  "${ACM_CERT_ARN}" \
  "ACM wildcard certificate ARN"

echo ""
echo "--- coder-provisioner/helmrelease.yaml ---"

patch_yaml \
  "${PROVISIONER_HR}" \
  '.spec.values.coder.serviceAccount.annotations."eks.amazonaws.com/role-arn"' \
  "${CODER_PROVISIONER_IRSA}" \
  "coder provisioner IRSA role ARN"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> Done."
if "${DRY_RUN}"; then
  echo "    Mode ........ dry-run (no files were modified)"
fi
echo "    Patched ..... ${PATCHED}"
echo "    Skipped ..... ${SKIPPED} (already set)"
echo "    Missing ..... ${MISSING} (terraform output not available)"

if [[ "${MISSING}" -gt 0 ]]; then
  echo ""
  echo "NOTE: Some Terraform outputs were not available. Ensure the"
  echo "      corresponding IRSA modules are defined and the layers"
  echo "      have been applied."
fi
