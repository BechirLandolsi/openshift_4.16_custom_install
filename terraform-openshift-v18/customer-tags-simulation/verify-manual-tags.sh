#!/bin/bash
# ==============================================================================
# Verify Manually Applied Subnet Tags
# ==============================================================================
# This script verifies that subnet tags were correctly applied manually.
#
# Usage: ./verify-manual-tags.sh [tfvars-file]
# Example: ./verify-manual-tags.sh env/demo.tfvars
# ==============================================================================

set -e

TFVARS_FILE="${1:-env/demo.tfvars}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Verify Manually Tagged Subnets                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo -e "${RED}✗ Error: tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

# Parse configuration
CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
INFRA_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')

PRIVATE_SUBNETS=$(grep '^aws_private_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
PUBLIC_SUBNETS=$(grep '^aws_public_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')

CLUSTER_TAG="kubernetes.io/cluster/${CLUSTER_NAME}-${INFRA_ID}"

echo -e "${CYAN}Expected Cluster Tag: ${YELLOW}${CLUSTER_TAG}${NC}"
echo

# Function to check subnet tags
check_subnet() {
    local subnet_id=$1
    local subnet_type=$2
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${subnet_type}: ${subnet_id}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    TAGS=$(aws ec2 describe-tags \
        --region "$REGION" \
        --filters "Name=resource-id,Values=${subnet_id}" \
        --query 'Tags[*].[Key,Value]' \
        --output text 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}✗ Error querying tags${NC}"
        return 1
    fi
    
    if [[ -z "$TAGS" ]]; then
        echo -e "${RED}✗ No tags found!${NC}"
        return 1
    fi
    
    # Display all tags
    echo "$TAGS" | awk '{printf "  %-50s = %s\n", $1, $2}'
    echo
    
    # Check for required cluster tag
    if echo "$TAGS" | grep -q "^${CLUSTER_TAG}"; then
        echo -e "${GREEN}✓ Required cluster tag found${NC}"
    else
        echo -e "${RED}✗ Missing cluster tag: ${CLUSTER_TAG}${NC}"
        return 1
    fi
    
    # Check role tags
    if [[ "$subnet_type" == "Private" ]]; then
        if echo "$TAGS" | grep -q "^kubernetes.io/role/internal-elb"; then
            echo -e "${GREEN}✓ Internal ELB role tag found${NC}"
        else
            echo -e "${YELLOW}⚠ Missing internal-elb role tag (optional)${NC}"
        fi
    elif [[ "$subnet_type" == "Public" ]]; then
        if echo "$TAGS" | grep -q "^kubernetes.io/role/elb"; then
            echo -e "${GREEN}✓ ELB role tag found${NC}"
        else
            echo -e "${YELLOW}⚠ Missing elb role tag${NC}"
        fi
    fi
    
    echo
}

# Check private subnets
for subnet in $PRIVATE_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        check_subnet "$subnet" "Private"
    fi
done

# Check public subnets
for subnet in $PUBLIC_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        check_subnet "$subnet" "Public"
    fi
done

echo -e "${GREEN}✓ Verification complete!${NC}"
echo
