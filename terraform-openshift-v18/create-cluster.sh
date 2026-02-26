#!/bin/bash
# ==============================================================================
# Create OpenShift Cluster
# ==============================================================================
# This script runs the OpenShift installer and starts a background process
# to create the *.apps DNS record in the private hosted zone.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create output directory
mkdir -p output

echo "=========================================="
echo "OpenShift Cluster Installation"
echo "=========================================="
echo "Start time: $(date)"

# Load cluster info from tfvars for DNS creation
# TFVARS_FILE must be set by Terraform via environment variable
if [[ -z "$TFVARS_FILE" ]]; then
    echo "ERROR: TFVARS_FILE environment variable is not set."
    echo "This script should be called by Terraform which passes the tfvars file."
    echo "If running manually, set: export TFVARS_FILE=env/your-cluster.tfvars"
    exit 1
fi

if [[ -f "$TFVARS_FILE" ]]; then
    CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    DOMAIN=$(grep '^domain' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    HOSTED_ZONE=$(grep '^hosted_zone' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    # Also load infra_random_id as fallback if not passed from Terraform
    if [[ -z "$INFRA_RANDOM_ID" ]]; then
        INFRA_RANDOM_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    fi
    echo "Loaded from tfvars ($TFVARS_FILE):"
    echo "  CLUSTER_NAME: $CLUSTER_NAME"
    echo "  DOMAIN: $DOMAIN"
    echo "  REGION: $REGION"
    echo "  HOSTED_ZONE: $HOSTED_ZONE"
    echo "  INFRA_RANDOM_ID: $INFRA_RANDOM_ID"
else
    echo "WARNING: No tfvars file found. DNS creation may fail."
fi

# Validate INFRA_RANDOM_ID is set (critical for InfraID consistency)
if [[ -z "$INFRA_RANDOM_ID" ]]; then
    echo "ERROR: INFRA_RANDOM_ID is not set!"
    echo "This is critical for cluster infrastructure naming."
    echo "Please ensure infra_random_id is defined in your tfvars file."
    exit 1
fi

# Set environment variables for custom installer
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"
echo ""
echo "Environment variables for installer:"
echo "  IgnoreErrorsOnSharedTags: $IgnoreErrorsOnSharedTags"
echo "  ForceOpenshiftInfraIDRandomPart: $ForceOpenshiftInfraIDRandomPart"

# Start background process to create DNS records (private and public zones)
# This solves the authentication operator deadlock:
# - Installer waits for authentication operator
# - Authentication needs *.apps DNS to resolve oauth-openshift
# - DNS must be created DURING install, not after
if [[ -n "$CLUSTER_NAME" ]] && [[ -n "$DOMAIN" ]] && [[ -n "$REGION" ]]; then
    echo ""
    echo "Starting background DNS creation for *.apps.${CLUSTER_NAME}.${DOMAIN}..."
    chmod +x create-private-dns.sh 2>/dev/null || true
    # Run with output to log file instead of /dev/null
    nohup ./create-private-dns.sh "$CLUSTER_NAME" "$DOMAIN" "$REGION" "${HOSTED_ZONE:-}" >> output/private-dns.log 2>&1 &
    DNS_PID=$!
    echo "Background DNS process started (PID: $DNS_PID)"
    echo "$DNS_PID" > output/dns-pid.txt
    echo ""
else
    echo "WARNING: Missing CLUSTER_NAME, DOMAIN, or REGION. DNS creation skipped."
    echo "  CLUSTER_NAME: ${CLUSTER_NAME:-MISSING}"
    echo "  DOMAIN: ${DOMAIN:-MISSING}"
    echo "  REGION: ${REGION:-MISSING}"
fi

echo ""
echo "=========================================="
echo "Starting OpenShift Installer"
echo "=========================================="

# Run the custom OpenShift installer
./openshift-install create cluster --dir=installer-files --log-level=debug