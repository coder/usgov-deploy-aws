#!/usr/bin/env bash
# dns-bootstrap.sh — Verify Route 53 hosted zone and ACM cert for coder4gov.com
#
# coder4gov.com is registered through AWS, so Route 53 is already authoritative.
# No delegation from external DNS providers is needed.
#
# This script is a pre-flight check to run AFTER terraform apply on 1-network.
# It verifies the R53 hosted zone exists and the ACM wildcard cert is issued.
#
# Prerequisites: aws CLI configured with access to the target account
set -euo pipefail

DOMAIN="coder4gov.com"
REGION="${AWS_REGION:-us-west-2}"

echo "=== DNS Bootstrap Check for ${DOMAIN} ==="
echo ""

# --- Step 1: Verify Route 53 hosted zone ---
echo "1. Checking Route 53 hosted zone..."
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${DOMAIN}" \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | head -1 | sed 's|/hostedzone/||')

if [ -z "$ZONE_ID" ]; then
  echo "   ✗ No hosted zone found for ${DOMAIN}"
  echo "   Run: terraform apply on infra/terraform/1-network/"
  exit 1
fi
echo "   ✓ Hosted zone: ${ZONE_ID}"

# --- Step 2: Verify nameservers match registrar ---
echo ""
echo "2. Checking nameservers match between registrar and hosted zone..."
R53_NS=$(aws route53 get-hosted-zone --id "${ZONE_ID}" \
  --query "DelegationSet.NameServers" --output text | sort)

REG_NS=$(aws route53domains get-domain-detail --domain-name "${DOMAIN}" \
  --query "Nameservers[].Name" --output text 2>/dev/null | sort || echo "")

if [ -z "$REG_NS" ]; then
  echo "   ⚠ Could not query registrar (route53domains API may not be available in ${REGION})"
  echo "   Hosted zone NS: ${R53_NS}"
  echo "   Manually verify these match the domain registrar nameservers."
else
  if [ "$R53_NS" = "$REG_NS" ]; then
    echo "   ✓ Nameservers match"
  else
    echo "   ✗ Nameserver MISMATCH"
    echo "   Hosted zone NS: ${R53_NS}"
    echo "   Registrar NS:   ${REG_NS}"
    echo "   Update the registrar to use the hosted zone nameservers."
    exit 1
  fi
fi

# --- Step 3: Verify ACM wildcard certificate ---
echo ""
echo "3. Checking ACM wildcard certificate for *.${DOMAIN}..."
CERT_ARN=$(aws acm list-certificates --region "${REGION}" \
  --query "CertificateSummaryList[?DomainName=='*.${DOMAIN}'].CertificateArn" \
  --output text | head -1)

if [ -z "$CERT_ARN" ]; then
  echo "   ✗ No ACM wildcard cert found for *.${DOMAIN}"
  echo "   Terraform 1-network should create this. Check the apply output."
  exit 1
fi

STATUS=$(aws acm describe-certificate --region "${REGION}" \
  --certificate-arn "${CERT_ARN}" \
  --query "Certificate.Status" --output text)

echo "   Certificate: ${CERT_ARN}"
echo "   Status: ${STATUS}"

if [ "$STATUS" = "ISSUED" ]; then
  echo "   ✓ Certificate is issued and ready"
elif [ "$STATUS" = "PENDING_VALIDATION" ]; then
  echo "   ⚠ Certificate is pending DNS validation"
  echo "   Terraform should create the validation records automatically."
  echo "   Wait a few minutes and re-run this script."
else
  echo "   ✗ Unexpected status: ${STATUS}"
  exit 1
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "Domain:      ${DOMAIN}"
echo "R53 Zone:    ${ZONE_ID}"
echo "ACM Cert:    ${STATUS}"
echo ""
echo "DNS records to expect after full deploy:"
echo "  dev.${DOMAIN}         → Coder ALB"
echo "  *.dev.${DOMAIN}       → Coder ALB (workspaces)"
