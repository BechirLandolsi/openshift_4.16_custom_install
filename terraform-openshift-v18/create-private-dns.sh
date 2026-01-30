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
REGION="${3:-}"
PUBLIC_ZONE_ID="${4:-}"

if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$DOMAIN" ]] || [[ -z "$REGION" ]]; then
    echo "[create-private-dns] Error: Missing arguments"
    echo "Usage: $0 <cluster_name> <domain> <region> [public_zone_id]"
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
# Step 1: Find the private hosted zone
# ==============================================================================
log "Step 1: Looking for private hosted zone..."

# The private zone could be either:
# 1. cluster.domain (e.g., cluster-name.example.com) - created by installer
# 2. domain only (e.g., example.com) - pre-existing shared zone

PRIVATE_ZONE_ID=""
PRIVATE_ZONE_NAME=""

for i in {1..60}; do
    # First try: cluster.domain (installer-created zone)
    PRIVATE_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Config.PrivateZone==\`true\` && Name=='${CLUSTER_NAME}.${DOMAIN}.'].Id" \
        --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')
    
    if [[ -n "$PRIVATE_ZONE_ID" ]] && [[ "$PRIVATE_ZONE_ID" != "None" ]]; then
        PRIVATE_ZONE_NAME="${CLUSTER_NAME}.${DOMAIN}"
        log "✓ Found cluster-specific private zone: $PRIVATE_ZONE_ID ($PRIVATE_ZONE_NAME)"
        break
    fi
    
    # Second try: domain only (shared private zone)
    PRIVATE_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Config.PrivateZone==\`true\` && Name=='${DOMAIN}.'].Id" \
        --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')
    
    if [[ -n "$PRIVATE_ZONE_ID" ]] && [[ "$PRIVATE_ZONE_ID" != "None" ]]; then
        PRIVATE_ZONE_NAME="${DOMAIN}"
        log "✓ Found domain-level private zone: $PRIVATE_ZONE_ID ($PRIVATE_ZONE_NAME)"
        break
    fi
    
    log "  Attempt $i/60: Private zone not found yet, waiting 10s..."
    sleep 10
done

if [[ -z "$PRIVATE_ZONE_ID" ]] || [[ "$PRIVATE_ZONE_ID" == "None" ]]; then
    log "✗ Private hosted zone not found after 10 minutes"
    log "  Looked for: ${CLUSTER_NAME}.${DOMAIN} or ${DOMAIN}"
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
    log "✓ Successfully created *.apps.${CLUSTER_NAME}.${DOMAIN} -> ${LB_HOSTNAME} (PRIVATE ZONE)"
    log "  Change info: $(echo "$RESULT" | jq -r '.ChangeInfo.Id // "N/A"')"
else
    log "✗ Failed to create private zone DNS record: $RESULT"
    # Continue anyway to try public zone
fi

# ==============================================================================
# Step 5: Create *.apps record in PUBLIC zone (for external access)
# ==============================================================================
if [[ -n "$PUBLIC_ZONE_ID" ]]; then
    log "Step 5: Creating *.apps CNAME record in PUBLIC zone..."
    
    # Check if record already exists in public zone
    EXISTING_PUBLIC=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$PUBLIC_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${RECORD_NAME}'].Name" \
        --output text 2>/dev/null)
    
    if [[ -n "$EXISTING_PUBLIC" ]] && [[ "$EXISTING_PUBLIC" != "None" ]]; then
        log "✓ Record already exists in public zone, skipping"
    else
        RESULT_PUBLIC=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$PUBLIC_ZONE_ID" \
            --change-batch "$CHANGE_BATCH" \
            --region "$REGION" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            log "✓ Successfully created *.apps.${CLUSTER_NAME}.${DOMAIN} -> ${LB_HOSTNAME} (PUBLIC ZONE)"
        else
            log "⚠ Failed to create public zone DNS record (may already exist as different type): $RESULT_PUBLIC"
        fi
    fi
else
    log "Step 5: Skipping public zone (no PUBLIC_ZONE_ID provided)"
fi

log "DNS record creation complete!"
