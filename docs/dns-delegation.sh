#!/usr/bin/env bash
# Delegate gov.demo.coder.com from Google Cloud DNS to AWS Route 53
# Run this AFTER terraform apply on infra/terraform/1-network/
# Prerequisites: gcloud CLI authenticated with access to demo.coder.com zone
#
# This script creates an NS record in the Google Cloud DNS zone for
# demo.coder.com that delegates gov.demo.coder.com to the AWS Route 53
# nameservers provisioned by Terraform. This allows Route 53 to be
# authoritative for all *.gov.demo.coder.com records.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PARENT_ZONE="demo-coder-com"               # GCP Cloud DNS managed zone name
DELEGATED_SUBDOMAIN="gov.demo.coder.com."  # Trailing dot required by Cloud DNS
TTL=300                                     # NS record TTL in seconds

# ---------------------------------------------------------------------------
# Get Route 53 nameservers
# ---------------------------------------------------------------------------
# Option 1: Read from terraform output (recommended)
#   cd to the 1-network layer and pull the nameservers automatically:
#
#   NAMESERVERS=$(
#     terraform -chdir=infra/terraform/1-network output -json route53_nameservers \
#       | jq -r '.[]'
#   )
#
# Option 2: Pass as arguments
#   ./dns-delegation.sh ns-111.awsdns-11.org ns-222.awsdns-22.co.uk ...

if [[ $# -gt 0 ]]; then
  NAMESERVERS=("$@")
else
  echo "Fetching Route 53 nameservers from terraform output..."
  mapfile -t NAMESERVERS < <(
    terraform -chdir=infra/terraform/1-network output -json route53_nameservers \
      | jq -r '.[]'
  )
fi

if [[ ${#NAMESERVERS[@]} -eq 0 ]]; then
  echo "ERROR: No nameservers provided. Pass them as arguments or ensure" >&2
  echo "       terraform output 'route53_nameservers' is available."      >&2
  exit 1
fi

echo "Nameservers to delegate to:"
printf "  %s\n" "${NAMESERVERS[@]}"
echo ""

# ---------------------------------------------------------------------------
# Create the NS delegation record in Google Cloud DNS
# ---------------------------------------------------------------------------
# Build the rrdatas argument — each NS needs a trailing dot.
NS_ARGS=()
for ns in "${NAMESERVERS[@]}"; do
  # Ensure trailing dot
  [[ "$ns" == *. ]] && NS_ARGS+=("$ns") || NS_ARGS+=("${ns}.")
done

echo "Creating NS record for ${DELEGATED_SUBDOMAIN} in zone ${PARENT_ZONE}..."
gcloud dns record-sets create "${DELEGATED_SUBDOMAIN}" \
  --zone="${PARENT_ZONE}" \
  --type="NS" \
  --ttl="${TTL}" \
  --rrdatas="$(IFS=,; echo "${NS_ARGS[*]}")"

echo ""
echo "NS record created successfully."

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
echo ""
echo "=== Verification ==="

echo ""
echo "1. Confirm the record exists in Cloud DNS:"
gcloud dns record-sets describe "${DELEGATED_SUBDOMAIN}" \
  --zone="${PARENT_ZONE}" \
  --type="NS"

echo ""
echo "2. Test DNS resolution (may take a few minutes to propagate):"
echo "   dig NS gov.demo.coder.com"
echo ""
echo "3. Verify the delegation chain:"
echo "   dig gov.demo.coder.com NS +trace"
echo ""
echo "Once propagation is complete, all *.gov.demo.coder.com records"
echo "will be resolved by the AWS Route 53 hosted zone."
