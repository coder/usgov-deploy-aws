#!/usr/bin/env bash
# =============================================================================
# seed-secrets.sh — Pre-deployment secret seeding & Bedrock model activation
# =============================================================================
# Run AFTER Terraform Layer 2 (which creates the Secrets Manager shells with
# PLACEHOLDER values) and BEFORE Layer 4/FluxCD (which consume the secrets).
#
# What this script does:
#   1. Seeds real values into AWS Secrets Manager for secrets that Terraform
#      created with placeholder values (OpenAI key, Gemini key, Coder license)
#   2. Submits the Anthropic First-Time Use (FTU) form for Bedrock model access
#   3. Verifies Bedrock model access with a test invocation
#   4. Optionally creates the three logical databases in RDS
#
# What this script does NOT touch (auto-populated by Terraform):
#   - coder4gov/rds-master-password  (random_password resource)
#   - coder4gov/ses-smtp-credentials (IAM access key resource)
#
# Usage:
#   ./seed-secrets.sh                          # Interactive — prompts for values
#   ./seed-secrets.sh --non-interactive        # Reads from environment variables
#   ./seed-secrets.sh --skip-bedrock           # Skip Bedrock activation
#   ./seed-secrets.sh --skip-secrets           # Skip secret seeding (Bedrock only)
#   ./seed-secrets.sh --skip-db                # Skip database creation
#
# Environment variables (for --non-interactive):
#   OPENAI_API_KEY     — OpenAI API key (sk-...)
#   GEMINI_API_KEY     — Google Gemini API key (AIza...)
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
SKIP_BEDROCK=false
SKIP_SECRETS=false
SKIP_DB=false

for arg in "$@"; do
  case "$arg" in
    --non-interactive) INTERACTIVE=false ;;
    --skip-bedrock)    SKIP_BEDROCK=true ;;
    --skip-secrets)    SKIP_SECRETS=true ;;
    --skip-db)         SKIP_DB=true ;;
    --help|-h)
      head -30 "$0" | grep '^#' | sed 's/^# \?//'
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

prompt_visible() {
  local var_name="$1" prompt_text="$2" env_val="${!1:-}"
  if [[ -n "$env_val" ]]; then
    echo "$env_val"
    return
  fi
  if [[ "$INTERACTIVE" == "false" ]]; then
    die "Environment variable $var_name is required in --non-interactive mode"
  fi
  read -rp "$prompt_text: " val
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
  info "Terraform created these secrets with PLACEHOLDER values."
  info "This script updates them with real values."
  echo ""

  # --- OpenAI API Key ---
  OPENAI_KEY=$(prompt_secret "OPENAI_API_KEY" "Enter OpenAI API key (sk-...)")
  aws secretsmanager put-secret-value \
    --region "$AWS_REGION" \
    --secret-id "${PROJECT_NAME}/openai-api-key" \
    --secret-string "{\"api_key\": \"${OPENAI_KEY}\"}" \
    --output text --query 'Name' 2>/dev/null \
    && ok "Updated ${PROJECT_NAME}/openai-api-key" \
    || die "Failed to update ${PROJECT_NAME}/openai-api-key"

  # --- Gemini API Key ---
  GEMINI_KEY=$(prompt_secret "GEMINI_API_KEY" "Enter Google Gemini API key (AIza...)")
  aws secretsmanager put-secret-value \
    --region "$AWS_REGION" \
    --secret-id "${PROJECT_NAME}/gemini-api-key" \
    --secret-string "{\"api_key\": \"${GEMINI_KEY}\"}" \
    --output text --query 'Name' 2>/dev/null \
    && ok "Updated ${PROJECT_NAME}/gemini-api-key" \
    || die "Failed to update ${PROJECT_NAME}/gemini-api-key"

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
  ok "All secrets seeded."

  # --- Verify (list all project secrets) ---
  info "Verifying secrets exist:"
  aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --filters "Key=name,Values=${PROJECT_NAME}/" \
    --query 'SecretList[*].[Name,CreatedDate]' \
    --output table
fi

# ============================================================================
# SECTION 2: Bedrock Model Activation
# ============================================================================
if [[ "$SKIP_BEDROCK" == "false" ]]; then
  echo ""
  info "=== Activating Bedrock Models ==="

  # Step 1: Check if Anthropic FTU has been submitted
  # In commercial regions, model access is auto-enabled on first invocation
  # but Anthropic requires a one-time use-case submission.
  info "Checking Anthropic model access..."

  # Try a lightweight invocation to trigger auto-subscription
  # If FTU is needed, this will fail with a specific error
  FTU_TEST=$(aws bedrock-runtime invoke-model \
    --region "$AWS_REGION" \
    --model-id "us.anthropic.claude-haiku-4-5-20251001-v1:0" \
    --content-type application/json \
    --accept application/json \
    --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":8,"messages":[{"role":"user","content":"Hi"}]}' \
    /dev/stdout 2>&1) && FTU_OK=true || FTU_OK=false

  if [[ "$FTU_OK" == "true" ]]; then
    ok "Anthropic models already accessible (FTU complete)"
  else
    if echo "$FTU_TEST" | grep -qi "AccessDeniedException"; then
      warn "Anthropic First-Time Use (FTU) form has not been submitted."
      warn "This is a ONE-TIME per-account requirement."
      echo ""
      info "Submitting Anthropic use-case details via CLI..."
      # The PutUseCaseForModelAccess API requires use-case text
      aws bedrock put-use-case-for-model-access \
        --region "$AWS_REGION" \
        --model-id "anthropic.claude-sonnet-4-6" \
        --use-case-details "Enterprise demo environment for Coder (coder4gov.com). Uses Claude models via LiteLLM proxy for AI-assisted software development in secure, FIPS-compliant workspaces." \
        2>/dev/null \
        && ok "Anthropic FTU submitted — access may take up to 2 minutes" \
        || warn "FTU API call failed. You may need to submit manually via the Bedrock console."

      info "Waiting 30 seconds for subscription to propagate..."
      sleep 30
    else
      warn "Unexpected error from Bedrock: $FTU_TEST"
      warn "You may need to check IAM permissions or submit FTU via console."
    fi
  fi

  # Step 2: Verify all three models are accessible
  echo ""
  info "Verifying Bedrock model access..."

  MODELS=(
    "us.anthropic.claude-sonnet-4-6|Claude Sonnet 4.6"
    "us.anthropic.claude-opus-4-6-v1|Claude Opus 4.6"
    "us.anthropic.claude-haiku-4-5-20251001-v1:0|Claude Haiku 4.5"
  )

  ALL_OK=true
  for entry in "${MODELS[@]}"; do
    MODEL_ID="${entry%%|*}"
    MODEL_NAME="${entry##*|}"

    RESULT=$(aws bedrock-runtime invoke-model \
      --region "$AWS_REGION" \
      --model-id "$MODEL_ID" \
      --content-type application/json \
      --accept application/json \
      --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":16,"messages":[{"role":"user","content":"Reply with exactly: FIPS_CHECK_OK"}]}' \
      /dev/stdout 2>/dev/null) && STATUS="ok" || STATUS="fail"

    if [[ "$STATUS" == "ok" ]] && echo "$RESULT" | jq -e '.content[0].text' &>/dev/null; then
      REPLY=$(echo "$RESULT" | jq -r '.content[0].text')
      ok "$MODEL_NAME ($MODEL_ID) — responded: $REPLY"
    else
      err "$MODEL_NAME ($MODEL_ID) — FAILED"
      ALL_OK=false
    fi
  done

  echo ""
  if [[ "$ALL_OK" == "true" ]]; then
    ok "All Bedrock models verified."
  else
    warn "Some models failed. Check the Bedrock console → Model access."
    warn "Docs: docs/BEDROCK_SETUP.md"
  fi
fi

# ============================================================================
# SECTION 3: Create logical databases in RDS
# ============================================================================
if [[ "$SKIP_DB" == "false" ]]; then
  echo ""
  info "=== Creating RDS Databases ==="
  info "The RDS instance hosts 3 logical databases: coder, litellm, keycloak"
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
    warn "Create the databases manually:"
    echo "  PGPASSWORD='...' psql -h $RDS_HOST -p $RDS_PORT -U $RDS_USER -d postgres"
    echo "  CREATE DATABASE coder;"
    echo "  CREATE DATABASE litellm;"
    echo "  CREATE DATABASE keycloak;"
  else
    export PGPASSWORD="$RDS_PASS"
    for DB in coder litellm keycloak; do
      if psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d postgres \
        -tAc "SELECT 1 FROM pg_database WHERE datname='$DB'" 2>/dev/null | grep -q 1; then
        ok "Database '$DB' already exists"
      else
        psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_USER" -d postgres \
          -c "CREATE DATABASE $DB;" 2>/dev/null \
          && ok "Created database '$DB'" \
          || err "Failed to create database '$DB'"
      fi
    done
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
echo "  Secrets Manager:  ${SKIP_SECRETS:+SKIPPED}${SKIP_SECRETS:- 3 secrets seeded}"
echo "  Bedrock Models:   ${SKIP_BEDROCK:+SKIPPED}${SKIP_BEDROCK:- 3 models verified}"
echo "  RDS Databases:    ${SKIP_DB:+SKIPPED}${SKIP_DB:- coder, litellm, keycloak}"
echo ""
echo "  Next steps:"
echo "    1. terraform apply layers 3-5 (if not done)"
echo "    2. Build Coder FIPS image: gh workflow run coder-fips.yml"
echo "    3. Fill FluxCD TODO placeholders from terraform output"
echo "    4. Push repo to GitLab, enable FluxCD"
echo "============================================================"
