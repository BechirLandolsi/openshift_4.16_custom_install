#!/bin/bash
# ==============================================================================
# Unlock Subnet Tags - Remove Immutability
# ==============================================================================
# This script removes the IAM policies that prevent tag modifications,
# restoring normal operations.
#
# Usage: ./unlock-subnet-tags.sh [tfvars-file]
# Example: ./unlock-subnet-tags.sh env/demo.tfvars
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
echo -e "${BLUE}║          Unlock Subnet Tags (Remove Restrictions)             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo -e "${RED}✗ Error: tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

# Parse configuration
echo -e "${CYAN}📋 Reading configuration...${NC}"

CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
ACCOUNT_ID=$(grep '^account_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
CONTROL_PLANE_ROLE=$(grep '^control_plane_role_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
WORKER_ROLE=$(grep '^aws_worker_iam_role' "$TFVARS_FILE" | awk -F'"' '{print $2}')

POLICY_NAME="${CLUSTER_NAME}-deny-subnet-tags"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo -e "${GREEN}✓ Policy to remove: ${POLICY_NAME}${NC}"
echo -e "${GREEN}✓ Control Plane Role: ${CONTROL_PLANE_ROLE}${NC}"
echo -e "${GREEN}✓ Worker Role: ${WORKER_ROLE}${NC}"
echo

echo -e "${YELLOW}This will remove IAM restrictions and allow tag modifications again.${NC}"
echo
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Detach from control plane role
echo -e "${CYAN}Detaching policy from control plane role...${NC}"
aws iam detach-role-policy \
    --role-name "$CONTROL_PLANE_ROLE" \
    --policy-arn "$POLICY_ARN" 2>&1 || echo -e "${YELLOW}⚠ Already detached or not found${NC}"

# Detach from worker role
echo -e "${CYAN}Detaching policy from worker role...${NC}"
aws iam detach-role-policy \
    --role-name "$WORKER_ROLE" \
    --policy-arn "$POLICY_ARN" 2>&1 || echo -e "${YELLOW}⚠ Already detached or not found${NC}"

# Delete the policy
echo -e "${CYAN}Deleting IAM policy...${NC}"
aws iam delete-policy \
    --policy-arn "$POLICY_ARN" 2>&1

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Policy deleted: ${POLICY_ARN}${NC}"
else
    echo -e "${YELLOW}⚠ Policy may not exist or already deleted${NC}"
fi

echo
echo -e "${GREEN}✓ Subnet tags are now UNLOCKED!${NC}"
echo -e "${CYAN}OpenShift can now modify subnet tags normally.${NC}"
echo
