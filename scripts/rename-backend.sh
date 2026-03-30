#!/usr/bin/env bash
#
# rename-backend.sh — Update Terraform backend blocks for a new project/region.
#
# Replaces the hard-coded bucket, DynamoDB table, and region values in every
# providers.tf under infra/terraform/ so you can fork the repo and point at
# your own state resources.
#
# Usage:
#   scripts/rename-backend.sh --project-name myproject --region us-gov-west-1

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────
OLD_PROJECT="coder4gov"
OLD_REGION="us-west-2"
PROJECT_NAME=""
REGION=""

# ── Parse flags ───────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") --project-name NAME --region REGION

Required flags:
  --project-name  New project name (e.g. myproject)
  --region        New AWS region   (e.g. us-gov-west-1)

Example:
  $(basename "$0") --project-name myproject --region us-gov-west-1
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Error: unknown flag '$1'" >&2
      usage
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Error: --project-name is required" >&2
  usage
fi

if [[ -z "$REGION" ]]; then
  echo "Error: --region is required" >&2
  usage
fi

# ── Locate repo root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

if [[ ! -d "$TF_DIR" ]]; then
  echo "Error: cannot find $TF_DIR" >&2
  exit 1
fi

# ── Apply replacements ───────────────────────────────────────────────────
changed=0

while IFS= read -r -d '' file; do
  modified=false

  # Replace bucket name: <old>-terraform-state → <new>-terraform-state
  if grep -q "${OLD_PROJECT}-terraform-state" "$file"; then
    sed -i "s/${OLD_PROJECT}-terraform-state/${PROJECT_NAME}-terraform-state/g" "$file"
    modified=true
  fi

  # Replace DynamoDB table: <old>-terraform-lock → <new>-terraform-lock
  if grep -q "${OLD_PROJECT}-terraform-lock" "$file"; then
    sed -i "s/${OLD_PROJECT}-terraform-lock/${PROJECT_NAME}-terraform-lock/g" "$file"
    modified=true
  fi

  # Replace hard-coded region inside backend blocks.
  # Only match lines with a literal region string (not var.aws_region).
  if grep -q "region.*=.*\"${OLD_REGION}\"" "$file"; then
    sed -i "s/region\([ ]*\)=\([ ]*\)\"${OLD_REGION}\"/region\1=\2\"${REGION}\"/g" "$file"
    modified=true
  fi

  if $modified; then
    echo "  updated: ${file#"$REPO_ROOT"/}"
    changed=$((changed + 1))
  fi
done < <(find "$TF_DIR" -name 'providers.tf' -print0)

echo ""
if [[ $changed -eq 0 ]]; then
  echo "No files needed changes (already up to date)."
else
  echo "Done — $changed file(s) updated."
  echo "  bucket:    ${PROJECT_NAME}-terraform-state"
  echo "  table:     ${PROJECT_NAME}-terraform-lock"
  echo "  region:    ${REGION}"
fi
