#!/bin/bash
# ==============================================================================
# Manually Tag Subnets to Simulate Customer Environment
# ==============================================================================
# This script tags your subnets with OpenShift-required tags WITHOUT modifying
# your Terraform configuration. This simulates a customer environment where
# subnets are pre-tagged.
#
# Usage: ./manual-tag-subnets.sh [tfvars-file]
# Example: ./manual-tag-subnets.sh env/demo.tfvars
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
echo -e "${BLUE}║        Manually Tag Subnets (Customer Simulation)             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo -e "${RED}✗ Error: tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

# Parse configuration
echo -e "${CYAN}📋 Reading configuration from: ${TFVARS_FILE}${NC}"

CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
INFRA_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
ACCOUNT_ID=$(grep '^account_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')

PRIVATE_SUBNETS=$(grep '^aws_private_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
PUBLIC_SUBNETS=$(grep '^aws_public_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')

echo -e "${GREEN}✓ Cluster Name: ${CLUSTER_NAME}${NC}"
echo -e "${GREEN}✓ Infra ID: ${INFRA_ID}${NC}"
echo -e "${GREEN}✓ Region: ${REGION}${NC}"
echo -e "${GREEN}✓ Account ID: ${ACCOUNT_ID}${NC}"
echo

if [[ -z "$CLUSTER_NAME" ]] || [[ -z "$INFRA_ID" ]]; then
    echo -e "${RED}✗ Error: Could not parse required variables${NC}"
    exit 1
fi

CLUSTER_TAG="kubernetes.io/cluster/${CLUSTER_NAME}-${INFRA_ID}"

echo -e "${YELLOW}This will tag your subnets with OpenShift-required tags.${NC}"
echo -e "${YELLOW}These tags simulate a customer environment with pre-tagged subnets.${NC}"
echo
echo -e "${CYAN}Tags to be applied:${NC}"
echo -e "  • ${CLUSTER_TAG}=shared"
echo -e "  • Name=${CLUSTER_NAME}-${INFRA_ID}-subnet"
echo -e "  • Environment=OpenShift"
echo -e "  • ManagedBy=Manual"
echo -e "  • TagProtection=Simulated"
echo
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Function to tag a subnet
tag_subnet() {
    local subnet_id=$1
    local subnet_type=$2
    local extra_tags=$3
    
    echo -e "${CYAN}Tagging ${subnet_type}: ${subnet_id}${NC}"
    
    # Apply base tags
    aws ec2 create-tags \
        --region "$REGION" \
        --resources "$subnet_id" \
        --tags \
            "Key=${CLUSTER_TAG},Value=shared" \
            "Key=Name,Value=${CLUSTER_NAME}-${INFRA_ID}-subnet" \
            "Key=Environment,Value=OpenShift" \
            "Key=ManagedBy,Value=Manual" \
            "Key=TagProtection,Value=Simulated" \
            $extra_tags \
        2>&1
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Tags applied to ${subnet_id}${NC}"
    else
        echo -e "${RED}✗ Failed to tag ${subnet_id}${NC}"
        return 1
    fi
}

# Tag private subnets
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Tagging Private Subnets${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for subnet in $PRIVATE_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        # Add internal-elb role tag for private subnets
        tag_subnet "$subnet" "Private Subnet" "Key=kubernetes.io/role/internal-elb,Value=1"
    fi
done

# Tag public subnets
if [[ -n "$PUBLIC_SUBNETS" ]]; then
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Tagging Public Subnets${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for subnet in $PUBLIC_SUBNETS; do
        if [[ -n "$subnet" ]]; then
            # Add elb role tag for public subnets
            tag_subnet "$subnet" "Public Subnet" "Key=kubernetes.io/role/elb,Value=1"
        fi
    done
fi

echo
echo -e "${GREEN}✓ All subnets have been tagged!${NC}"
echo
echo -e "${CYAN}Next Steps:${NC}"
echo "1. Verify tags: ./verify-manual-tags.sh $TFVARS_FILE"
echo "2. Make tags immutable: ./lock-subnet-tags.sh $TFVARS_FILE"
echo "3. Run Terraform: terraform apply -var-file=$TFVARS_FILE"
echo
