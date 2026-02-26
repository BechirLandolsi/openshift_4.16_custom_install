#!/bin/bash
# Get the ingress load balancer ARN for Terraform external data source
# Returns JSON with LoadBalancerArn
#
# IMPORTANT: OpenShift 4.16 uses Network Load Balancers (NLB) which require
# the elbv2 API, not the classic elb API.

set -e

# Parse input from Terraform data.external
eval "$(jq -r '@sh "bucket=\(.bucket) region=\(.region)"')"

OUTPUTDIR=.
ERRORFILE="$OUTPUTDIR/get_ingress_error.log"
STDFILE="$OUTPUTDIR/get_ingress_exec.log"
KUBECONFIG="installer-files/auth/kubeconfig"

# Use region from Terraform if provided, otherwise try to detect
if [ -z "$region" ] || [ "$region" == "null" ]; then
    region=$(aws configure get region 2>/dev/null || echo "")
fi

# Function to output JSON result
output_result() {
    local arn="$1"
    jq -n --arg arn "$arn" '{"LoadBalancerArn": $arn}'
}

# Function to get dummy ARN (for destroy when cluster doesn't exist)
get_dummy_arn() {
    local r="${region:-eu-west-3}"
    local account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "000000000000")
    echo "arn:aws:elasticloadbalancing:${r}:${account}:loadbalancer/net/dummy/0000000000000000"
}

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$STDFILE"
}

# Clear previous logs
> "$ERRORFILE"
> "$STDFILE"

log "Starting get-ingress-lb.sh"

# Check if kubeconfig exists - if not, return dummy value (for destroy)
if [[ ! -f "$KUBECONFIG" ]]; then
    log "Kubeconfig not found, returning dummy ARN for terraform destroy"
    output_result "$(get_dummy_arn)"
    exit 0
fi

# Wait for ingress service to have a hostname
log "Waiting for ingress hostname..."
MAX_RETRIES=60
RETRY_COUNT=0
INGRESS_HOST=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    INGRESS_HOST=$(KUBECONFIG=$KUBECONFIG oc -n openshift-ingress get service router-default \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>>"$ERRORFILE" || echo "")
    
    if [ -n "$INGRESS_HOST" ] && [ "$INGRESS_HOST" != "null" ]; then
        log "Got ingress hostname: $INGRESS_HOST"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log "Attempt $RETRY_COUNT/$MAX_RETRIES: Waiting for ingress hostname..."
    sleep 10
done

if [ -z "$INGRESS_HOST" ] || [ "$INGRESS_HOST" == "null" ]; then
    log "ERROR: Failed to get ingress hostname after $MAX_RETRIES retries"
    echo "Failed to get ingress hostname" >> "$ERRORFILE"
    exit 1
fi

# Determine region (priority: Terraform input > hostname extraction > AWS config)
REGION=""

# 1. Use region from Terraform input if available
if [ -n "$region" ] && [ "$region" != "null" ]; then
    REGION="$region"
    log "Using region from Terraform: $REGION"
fi

# 2. Try to extract from hostname (format: xxx.REGION.elb.amazonaws.com)
if [ -z "$REGION" ]; then
    # Use sed for better portability (grep -P not available everywhere)
    REGION=$(echo "$INGRESS_HOST" | sed -n 's/.*\.\([a-z][a-z]-[a-z]*-[0-9]\)\.elb.*/\1/p')
    if [ -n "$REGION" ]; then
        log "Extracted region from hostname: $REGION"
    fi
fi

# 3. Fallback to AWS CLI config
if [ -z "$REGION" ]; then
    REGION=$(aws configure get region 2>/dev/null || echo "")
    if [ -n "$REGION" ]; then
        log "Using region from AWS config: $REGION"
    fi
fi

# 4. Final check - fail if no region found
if [ -z "$REGION" ]; then
    log "ERROR: Failed to determine AWS region"
    log "  - Terraform input: $region"
    log "  - Hostname: $INGRESS_HOST"
    log "  - AWS config: $(aws configure get region 2>/dev/null || echo 'not set')"
    echo "Failed to determine AWS region from Terraform, hostname, or AWS config" >> "$ERRORFILE"
    exit 1
fi

log "Using region: $REGION"

# Get the NLB ARN using elbv2 API (OpenShift 4.16 uses NLB)
log "Searching for NLB with DNS name: $INGRESS_HOST"

LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?DNSName=='${INGRESS_HOST}'].LoadBalancerArn" \
    --output text 2>>"$ERRORFILE")

log "First attempt result: $LB_ARN"

# If not found, try case-insensitive search
if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ]; then
    log "Trying case-insensitive search..."
    INGRESS_HOST_LOWER=$(echo "$INGRESS_HOST" | tr '[:upper:]' '[:lower:]')
    
    LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" --output json 2>>"$ERRORFILE" | \
        jq -r --arg host "$INGRESS_HOST_LOWER" \
        '.LoadBalancers[] | select(.DNSName | ascii_downcase == $host) | .LoadBalancerArn')
    
    log "Case-insensitive result: $LB_ARN"
fi

# If still not found, list all NLBs and find by partial match
if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ] || [ "$LB_ARN" == "null" ]; then
    log "Trying partial hostname match..."
    
    # Extract the unique part of the hostname (before the first dot)
    HOST_PREFIX=$(echo "$INGRESS_HOST" | cut -d'.' -f1)
    log "Looking for LB with prefix: $HOST_PREFIX"
    
    LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" --output json 2>>"$ERRORFILE" | \
        jq -r --arg prefix "$HOST_PREFIX" \
        '.LoadBalancers[] | select(.DNSName | startswith($prefix)) | .LoadBalancerArn' | head -1)
    
    log "Partial match result: $LB_ARN"
fi

# Validate we got a valid ARN
if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ] || [ "$LB_ARN" == "null" ]; then
    log "ERROR: Could not find load balancer ARN"
    log "Ingress hostname was: $INGRESS_HOST"
    log "Listing all NLBs in region $REGION for debugging:"
    aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[*].[LoadBalancerName,DNSName]" \
        --output text >> "$STDFILE" 2>>"$ERRORFILE"
    
    echo "Could not find NLB with hostname: $INGRESS_HOST" >> "$ERRORFILE"
    exit 1
fi

log "SUCCESS: Found LoadBalancerArn: $LB_ARN"

# Output JSON for Terraform
output_result "$LB_ARN"
