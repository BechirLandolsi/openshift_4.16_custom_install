#!/bin/bash
# ==============================================================================
# Create OpenShift Cluster
# ==============================================================================
# This script runs the OpenShift installer and starts a background process
# to create the *.apps DNS record in the private hosted zone.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load cluster info from tfvars for DNS creation
TFVARS_FILE="${TFVARS_FILE:-env/demo.tfvars}"
if [[ -f "$TFVARS_FILE" ]]; then
    CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    DOMAIN=$(grep '^domain' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    HOSTED_ZONE=$(grep '^hosted_zone' "$TFVARS_FILE" | awk -F'"' '{print $2}')
fi

# Set environment variables for custom installer
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"

# Start background process to create DNS records (private and public zones)
# This solves the authentication operator deadlock
if [[ -n "$CLUSTER_NAME" ]] && [[ -n "$DOMAIN" ]]; then
    echo "Starting background DNS creation for *.apps.${CLUSTER_NAME}.${DOMAIN}..."
    chmod +x create-private-dns.sh 2>/dev/null || true
    nohup ./create-private-dns.sh "$CLUSTER_NAME" "$DOMAIN" "${REGION:-eu-west-3}" "${HOSTED_ZONE:-}" > /dev/null 2>&1 &
    echo "Background DNS process started (PID: $!)"
fi

# Run the custom OpenShift installer
./openshift-install create cluster --dir=installer-files --log-level=debug