#!/usr/bin/env bash
# =============================================================================
# seed-secrets.sh — Pre-deployment secret seeding for Coder
# =============================================================================
# Run AFTER Terraform Layer 2 (which creates the Secrets Manager shells with
# PLACEHOLDER values) and BEFORE Layer 4/FluxCD (which consume the secrets).
#
# What this script does:
#   1. Seeds the Coder enterprise license into AWS Secrets Manager
#   2. Optionally creates the Coder logical database in RDS
#
# What this script does NOT touch (auto-populated by Terraform):
#   - coder4gov/rds-master-password  (random_password resource)
#
# Usage:
#   ./seed-secrets.sh                          # Interactive — prompts for values
#   ./seed-secrets.sh --non-interactive        # Reads from environment variables
#   ./seed-secrets.sh --skip-secrets           # Skip secret seeding
#   ./seed-secrets.sh --skip-db                # Skip database creation
#
# Environment variables (for --non-interactive):
#   CODER_LICENSE      — Coder enterprise license JWT
#   AWS_REGION         — AWS region (default: us-west-2)
#   PROJECT_NAME       — Project prefix (default: coder4gov)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults & flags
# ---------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-west-2}"
PROJECT_NAME="${PROJECT_NAME:-coder4gov}"
INTERACTIVE=true
SKIP_SECRETS=false
SKIP_DB=false

for arg in "$@"; do
  case "$arg" in
    --non-interactive) INTERACTIVE=false ;;
    --skip-secrets)    SKIP_SECRETS=true ;;
    --skip-db)         SKIP_DB=true ;;
    --help|-h)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die()   { err "$@"; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "'$1' is required but not found in PATH"
}

# Prompt for a value (masked input for secrets)
prompt_secret() {
  local var_name="$1" prompt_text="$2" env_val="${!1:-}"
  if [[ -n "$env_val" ]]; then
    echo "$env_val"
    return
  fi
  if [[ "$INTERACTIVE" == "false" ]]; then
    die "Environment variable $var_name is required in --non-interactive mode"
  fi
  read -rsp "$prompt_text: " val
  echo >&2  # newline after masked input
  [[ -n "$val" ]] || die "$var_name cannot be empty"
  echo "$val"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
require_cmd aws
require_cmd jq

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || die "AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE."
info "AWS Account: $ACCOUNT_ID | Region: $AWS_REGION"

# ============================================================================
# SECTION 1: Seed Secrets Manager
# ============================================================================
if [[ "$SKIP_SECRETS" == "false" ]]; then
  echo ""
  info "=== Seeding Secrets Manager ==="
  info "Terraform created the Coder license secret with a PLACEHOLDER value."
  info "This script updates it with the real value."
  echo ""

  # --- Coder License ---
  LICENSE=$(prompt_secret "CODER_LICENSE" "Enter Coder enterprise license JWT")
  aws secretsmanager put-secret-value \
    --region "$AWS_REGION" \
    --secret-id "${PROJECT_NAME}/coder-license" \
    --secret-string "{\"license\": \"${LICENSE}\"}" \
    --output text --query 'Name' 2>/dev/null \
    && ok "Updated ${PROJECT_NAME}/coder-license" \
    || die "Failed to update ${PROJECT_NAME}/coder-license"

  echo ""
  ok "Coder license seeded."

  # --- Verify (list all project secrets) ---
  info "Verifying secrets exist:"
  aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --filters "Key=name,Values=${PROJECT_NAME}/" \
    --query 'SecretList[*].[Name,CreatedDate]' \
    --output table
fi

# ============================================================================
# SECTION 2: Create Coder database in RDS
# ============================================================================
if [[ "$SKIP_DB" == "false" ]]; then
  echo ""
  info "=== Creating RDS Database ==="
  info "Fetching RDS credentials from Secrets Manager..."

  RDS_SECRET=$(aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "${PROJECT_NAME}/rds-master-password" \
    --query 'SecretString' --output text 2>/dev/null) \
    || die "Could not read RDS secret. Has Layer 2 been applied?"

  RDS_HOST=$(echo "$RDS_SECRET" | jq -r '.host')
  RDS_PORT=$(echo "$RDS_SECRET" | jq -r '.port')
  RDS_USER=$(echo "$RDS_SECRET" | jq -r '.username')
  RDS_PASS=$(echo "$RDS_SECRET" | jq -r '.password')

  if ! command -v psql &>/dev/null; then
    warn "'psql' not found — skipping database creation."
    warn "Create the database manually:"
    echo "  PGPASSWORD='...' psql -h $RDS_HOST -p $RDS_PORT -U $RDS_USER -d postgres"
    echo "  CREATE DATABASE coder;"
  else
    export PGPASSWORD="$RDS_PASS"
    if psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d postgres \
      -tAc "SELECT 1 FROM pg_database WHERE datname='coder'" 2>/dev/null | grep -q 1; then
      ok "Database 'coder' already exists"
    else
      psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d postgres \
        -c "CREATE DATABASE coder;" 2>/dev/null \
        && ok "Created database 'coder'" \
        || err "Failed to create database 'coder'"
    fi
    unset PGPASSWORD
  fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "============================================================"
info "Bootstrap complete."
echo ""
echo "  Secrets Manager:  ${SKIP_SECRETS:+SKIPPED}${SKIP_SECRETS:- Coder license seeded}"
echo "  RDS Database:     ${SKIP_DB:+SKIPPED}${SKIP_DB:- coder}"
echo ""
echo "  Next steps:"
echo "    1. terraform apply layers 3-4 (if not done)"
echo "    2. Build Coder FIPS image: gh workflow run coder-fips.yml"
echo "    3. Apply Flux manifests or bootstrap FluxCD"
echo "============================================================"
