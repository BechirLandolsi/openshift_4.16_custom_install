#!/bin/bash
# Get the ingress load balancer ARN for Terraform external data source
# Returns JSON with LoadBalancerArn
# Returns dummy value if cluster doesn't exist (for terraform destroy)

eval "$(jq -r '@sh "bucket=\(.bucket)"')"

OUTPUTDIR=.
ERRORFILE=$OUTPUTDIR/get_ingress_error.log
STDFILE=$OUTPUTDIR/get_ingress_exec.log

# Get kubeconfig path
KUBECONFIG="installer-files/auth/kubeconfig"

# Check if kubeconfig exists - if not, return dummy value (for destroy)
if [[ ! -f "$KUBECONFIG" ]]; then
    # Get region and account for dummy ARN (from AWS CLI config)
    REGION=$(aws configure get region 2>/dev/null)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    # Use placeholder if AWS CLI not configured
    REGION="${REGION:-us-east-1}"
    ACCOUNT_ID="${ACCOUNT_ID:-000000000000}"
    # Return a dummy ARN for terraform destroy to proceed
    jq -n --arg region "$REGION" --arg account "$ACCOUNT_ID" \
        '{"LoadBalancerArn": "arn:aws:elasticloadbalancing:\($region):\($account):loadbalancer/net/dummy/0000000000000000"}'
    exit 0
fi

# Wait for ingress to be ready and get the hostname
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Get the ingress service hostname
    INGRESS_HOST=$(KUBECONFIG=$KUBECONFIG oc -n openshift-ingress get service router-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$ERRORFILE || echo "")
    
    if [ -n "$INGRESS_HOST" ] && [ "$INGRESS_HOST" != "" ]; then
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 10
done

if [ -z "$INGRESS_HOST" ] || [ "$INGRESS_HOST" == "" ]; then
    echo "Failed to get ingress hostname after $MAX_RETRIES retries" >> $ERRORFILE
    exit 1
fi

# Extract the ELB/NLB name from hostname
# Format: <name>-<hash>.<region>.elb.amazonaws.com
LB_NAME=$(echo "$INGRESS_HOST" | cut -d'.' -f1 | cut -d'-' -f1-2)

# Get the region from hostname
REGION=$(echo "$INGRESS_HOST" | sed -n 's/.*\.\([a-z]*-[a-z]*-[0-9]*\)\.elb\.amazonaws\.com/\1/p')

if [ -z "$REGION" ]; then
    # Try to get region from AWS config or environment
    REGION=$(aws configure get region 2>/dev/null)
    if [ -z "$REGION" ]; then
        echo "Failed to determine AWS region from hostname or AWS config" >> $ERRORFILE
        exit 1
    fi
fi

# Try to find the load balancer ARN
# First try NLB (elbv2)
LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?DNSName=='$INGRESS_HOST'].LoadBalancerArn" \
    --output text 2>>$ERRORFILE || echo "")

# If not found in elbv2, try classic ELB
if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ] || [ "$LB_ARN" == "" ]; then
    # For classic ELB, construct the ARN
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>>$ERRORFILE)
    
    # Get classic ELB info
    ELB_INFO=$(aws elb describe-load-balancers --region "$REGION" \
        --query "LoadBalancerDescriptions[?DNSName=='$INGRESS_HOST'].LoadBalancerName" \
        --output text 2>>$ERRORFILE || echo "")
    
    if [ -n "$ELB_INFO" ] && [ "$ELB_INFO" != "None" ] && [ "$ELB_INFO" != "" ]; then
        LB_ARN="arn:aws:elasticloadbalancing:${REGION}:${ACCOUNT_ID}:loadbalancer/${ELB_INFO}"
    fi
fi

# If still not found, try to get any NLB/ALB matching the cluster
if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ] || [ "$LB_ARN" == "" ]; then
    # Search by DNS name pattern
    LB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?contains(DNSName, 'elb.amazonaws.com')].LoadBalancerArn | [0]" \
        --output text 2>>$ERRORFILE || echo "")
fi

if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ] || [ "$LB_ARN" == "" ]; then
    echo "Failed to find load balancer ARN for hostname: $INGRESS_HOST" >> $ERRORFILE
    exit 5
fi

# Output JSON for Terraform external data source
jq -n --arg arn "$LB_ARN" '{"LoadBalancerArn": $arn}'
