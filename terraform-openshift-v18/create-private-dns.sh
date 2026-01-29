#!/bin/bash
# ==============================================================================
# Create Private Zone DNS Record
# ==============================================================================
# This script runs in the background during cluster install to create the
# *.apps wildcard record in the private hosted zone as soon as possible.
#
# This solves the authentication operator deadlock:
# - Installer waits for authentication operator
# - Authentication needs *.apps DNS to resolve oauth-openshift
# - DNS must be created DURING install, not after
# ==============================================================================

CLUSTER_NAME="${1:-}"
DOMAIN="${2:-}"
REGION="${3:-eu-west-3}"

if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$DOMAIN" ]]; then
    echo "[create-private-dns] Error: Missing arguments"
    echo "Usage: $0 <cluster_name> <domain> [region]"
    exit 1
fi

LOG_FILE="output/private-dns.log"
mkdir -p output

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting private DNS record creation for ${CLUSTER_NAME}.${DOMAIN}"
log "Will create: *.apps.${CLUSTER_NAME}.${DOMAIN}"

# ==============================================================================
# Step 1: Wait for private hosted zone to exist
# ==============================================================================
log "Step 1: Waiting for private hosted zone..."

PRIVATE_ZONE_ID=""
for i in {1..60}; do
    PRIVATE_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name "${CLUSTER_NAME}.${DOMAIN}." \
        --query "HostedZones[?Config.PrivateZone==\`true\` && Name=='${CLUSTER_NAME}.${DOMAIN}.'].Id" \
        --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')
    
    if [[ -n "$PRIVATE_ZONE_ID" ]] && [[ "$PRIVATE_ZONE_ID" != "None" ]]; then
        log "✓ Found private hosted zone: $PRIVATE_ZONE_ID"
        break
    fi
    
    log "  Attempt $i/60: Private zone not found yet, waiting 10s..."
    sleep 10
done

if [[ -z "$PRIVATE_ZONE_ID" ]] || [[ "$PRIVATE_ZONE_ID" == "None" ]]; then
    log "✗ Private hosted zone not found after 10 minutes"
    exit 1
fi

# ==============================================================================
# Step 2: Wait for ingress router service to get LoadBalancer
# ==============================================================================
log "Step 2: Waiting for ingress LoadBalancer..."

KUBECONFIG="installer-files/auth/kubeconfig"
LB_HOSTNAME=""

for i in {1..90}; do
    # First check if kubeconfig exists
    if [[ ! -f "$KUBECONFIG" ]]; then
        log "  Attempt $i/90: Kubeconfig not ready yet, waiting 10s..."
        sleep 10
        continue
    fi
    
    # Try to get the LoadBalancer hostname
    LB_HOSTNAME=$(KUBECONFIG="$KUBECONFIG" oc get svc -n openshift-ingress router-default \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if [[ -n "$LB_HOSTNAME" ]] && [[ "$LB_HOSTNAME" != "null" ]]; then
        log "✓ Found ingress LoadBalancer: $LB_HOSTNAME"
        break
    fi
    
    log "  Attempt $i/90: LoadBalancer not ready yet, waiting 10s..."
    sleep 10
done

if [[ -z "$LB_HOSTNAME" ]] || [[ "$LB_HOSTNAME" == "null" ]]; then
    log "✗ Ingress LoadBalancer not found after 15 minutes"
    exit 1
fi

# ==============================================================================
# Step 3: Check if record already exists
# ==============================================================================
log "Step 3: Checking if *.apps record already exists..."

RECORD_NAME="*.apps.${CLUSTER_NAME}.${DOMAIN}."
EXISTING=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$PRIVATE_ZONE_ID" \
    --query "ResourceRecordSets[?Name=='${RECORD_NAME}'].Name" \
    --output text 2>/dev/null)

if [[ -n "$EXISTING" ]] && [[ "$EXISTING" != "None" ]]; then
    log "✓ Record already exists, skipping creation"
    exit 0
fi

# ==============================================================================
# Step 4: Create the *.apps CNAME record
# ==============================================================================
log "Step 4: Creating *.apps CNAME record..."

CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "${RECORD_NAME}",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value": "${LB_HOSTNAME}"}]
        }
    }]
}
EOF
)

RESULT=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$PRIVATE_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --region "$REGION" 2>&1)

if [[ $? -eq 0 ]]; then
    log "✓ Successfully created *.apps.${CLUSTER_NAME}.${DOMAIN} -> ${LB_HOSTNAME}"
    log "  Change info: $(echo "$RESULT" | jq -r '.ChangeInfo.Id // "N/A"')"
else
    log "✗ Failed to create DNS record: $RESULT"
    exit 1
fi

log "Private DNS record creation complete!"
