#!/bin/bash
# ==============================================================================
# Cleanup Manual Tags and Restrictions
# ==============================================================================
# This script removes all manual tags and IAM restrictions created for testing.
# Use this to restore your environment to its original state.
#
# Usage: ./cleanup-manual-tags.sh [tfvars-file]
# Example: ./cleanup-manual-tags.sh env/demo.tfvars
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
echo -e "${BLUE}║        Cleanup Manual Tags & Restrictions                     ║${NC}"
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
ACCOUNT_ID=$(grep '^account_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')

PRIVATE_SUBNETS=$(grep '^aws_private_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | tr -d ' ' | grep -v '^$')
PUBLIC_SUBNETS=$(grep '^aws_public_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | tr -d ' ' | grep -v '^$')

CLUSTER_TAG="kubernetes.io/cluster/${CLUSTER_NAME}-${INFRA_ID}"

echo -e "${YELLOW}⚠ WARNING: This will:${NC}"
echo -e "  1. Remove IAM deny policies (unlock tags)"
echo -e "  2. Remove manually applied tags from subnets"
echo -e "  3. Restore environment to original state"
echo
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

echo
echo -e "${CYAN}Step 1: Unlocking subnet tags (removing IAM policies)...${NC}"
bash "$(dirname "$0")/unlock-subnet-tags.sh" "$TFVARS_FILE" || echo -e "${YELLOW}⚠ Already unlocked${NC}"

echo
echo -e "${CYAN}Step 2: Removing tags from subnets...${NC}"

# Function to remove tags
remove_tags() {
    local subnet_id=$1
    local subnet_type=$2
    
    echo -e "${CYAN}  Removing tags from ${subnet_type}: ${subnet_id}${NC}"
    
    # Remove OpenShift cluster tag
    aws ec2 delete-tags \
        --region "$REGION" \
        --resources "$subnet_id" \
        --tags \
            "Key=${CLUSTER_TAG}" \
            "Key=Name" \
            "Key=Environment" \
            "Key=ManagedBy" \
            "Key=TagProtection" \
            "Key=kubernetes.io/role/elb" \
            "Key=kubernetes.io/role/internal-elb" \
        2>/dev/null || true
    
    echo -e "${GREEN}  ✓ Tags removed from ${subnet_id}${NC}"
}

# Remove tags from private subnets
for subnet in $PRIVATE_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        remove_tags "$subnet" "Private Subnet"
    fi
done

# Remove tags from public subnets
for subnet in $PUBLIC_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        remove_tags "$subnet" "Public Subnet"
    fi
done

echo
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo
echo -e "${CYAN}Environment restored to original state:${NC}"
echo -e "  • IAM deny policies removed"
echo -e "  • Manual subnet tags removed"
echo -e "  • OpenShift can now tag subnets normally"
echo
