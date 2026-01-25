#!/bin/bash
# ==============================================================================
# Lock Subnet Tags - Make Tags Immutable
# ==============================================================================
# This script creates IAM policies that prevent OpenShift roles from modifying
# subnet tags. This simulates a customer environment with tag restrictions.
#
# IMPORTANT: This creates IAM policies OUTSIDE of Terraform!
# You'll need to manually clean these up later.
#
# Usage: ./lock-subnet-tags.sh [tfvars-file]
# Example: ./lock-subnet-tags.sh env/demo.tfvars
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
echo -e "${BLUE}║          Lock Subnet Tags (Customer Simulation)               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo -e "${RED}✗ Error: tfvars file not found: $TFVARS_FILE${NC}"
    exit 1
fi

# Parse configuration
echo -e "${CYAN}📋 Reading configuration...${NC}"

CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
ACCOUNT_ID=$(grep '^account_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
CONTROL_PLANE_ROLE=$(grep '^control_plane_role_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
WORKER_ROLE=$(grep '^aws_worker_iam_role' "$TFVARS_FILE" | awk -F'"' '{print $2}')

PRIVATE_SUBNETS=$(grep '^aws_private_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | tr -d ' ' | grep -v '^$')
PUBLIC_SUBNETS=$(grep '^aws_public_subnets' "$TFVARS_FILE" | sed 's/.*= \[//' | sed 's/\]//' | tr ',' '\n' | tr -d '"' | tr -d ' ' | grep -v '^$')

echo -e "${GREEN}✓ Control Plane Role: ${CONTROL_PLANE_ROLE}${NC}"
echo -e "${GREEN}✓ Worker Role: ${WORKER_ROLE}${NC}"
echo -e "${GREEN}✓ Region: ${REGION}${NC}"
echo

if [[ -z "$CONTROL_PLANE_ROLE" ]] || [[ -z "$WORKER_ROLE" ]]; then
    echo -e "${RED}✗ Error: Could not parse IAM role names${NC}"
    exit 1
fi

POLICY_NAME="${CLUSTER_NAME}-deny-subnet-tags"

echo -e "${YELLOW}⚠ WARNING: This will create IAM policies OUTSIDE of Terraform!${NC}"
echo -e "${YELLOW}   These policies will DENY tag modifications on subnets for:${NC}"
echo -e "${YELLOW}   • ${CONTROL_PLANE_ROLE}${NC}"
echo -e "${YELLOW}   • ${WORKER_ROLE}${NC}"
echo
echo -e "${CYAN}This simulates a customer environment with strict tag policies.${NC}"
echo
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Build subnet ARNs
SUBNET_ARNS=""
for subnet in $PRIVATE_SUBNETS $PUBLIC_SUBNETS; do
    if [[ -n "$subnet" ]]; then
        if [[ -z "$SUBNET_ARNS" ]]; then
            SUBNET_ARNS="\"arn:aws:ec2:${REGION}:${ACCOUNT_ID}:subnet/${subnet}\""
        else
            SUBNET_ARNS="${SUBNET_ARNS},\"arn:aws:ec2:${REGION}:${ACCOUNT_ID}:subnet/${subnet}\""
        fi
    fi
done

# Create IAM policy document
POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenySubnetTagModifications",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": [
        ${SUBNET_ARNS}
      ]
    }
  ]
}
EOF
)

echo -e "${CYAN}Creating IAM deny policy: ${POLICY_NAME}${NC}"

# Create the policy
POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC" \
    --description "Deny subnet tag modifications for OpenShift (Customer Simulation)" \
    --query 'Policy.Arn' \
    --output text 2>&1)

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Policy created: ${POLICY_ARN}${NC}"
else
    if echo "$POLICY_ARN" | grep -q "EntityAlreadyExists"; then
        echo -e "${YELLOW}⚠ Policy already exists, retrieving ARN...${NC}"
        POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
        echo -e "${GREEN}✓ Using existing policy: ${POLICY_ARN}${NC}"
    else
        echo -e "${RED}✗ Failed to create policy:${NC}"
        echo "$POLICY_ARN"
        exit 1
    fi
fi

# Attach to control plane role
echo -e "${CYAN}Attaching policy to control plane role...${NC}"
aws iam attach-role-policy \
    --role-name "$CONTROL_PLANE_ROLE" \
    --policy-arn "$POLICY_ARN" 2>&1

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Policy attached to ${CONTROL_PLANE_ROLE}${NC}"
else
    echo -e "${RED}✗ Failed to attach policy to control plane role${NC}"
fi

# Attach to worker role
echo -e "${CYAN}Attaching policy to worker role...${NC}"
aws iam attach-role-policy \
    --role-name "$WORKER_ROLE" \
    --policy-arn "$POLICY_ARN" 2>&1

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ Policy attached to ${WORKER_ROLE}${NC}"
else
    echo -e "${RED}✗ Failed to attach policy to worker role${NC}"
fi

echo
echo -e "${GREEN}✓ Subnet tags are now IMMUTABLE!${NC}"
echo
echo -e "${YELLOW}Note: IAM policy changes can take a few minutes to propagate.${NC}"
echo
echo -e "${CYAN}What was created (OUTSIDE of Terraform):${NC}"
echo -e "  • IAM Policy: ${POLICY_NAME}"
echo -e "  • Policy ARN: ${POLICY_ARN}"
echo -e "  • Attached to: ${CONTROL_PLANE_ROLE}, ${WORKER_ROLE}"
echo
echo -e "${CYAN}Next Steps:${NC}"
echo "1. Wait 2-3 minutes for IAM changes to propagate"
echo "2. Run: cd .. && terraform apply -var-file=$TFVARS_FILE"
echo "3. Watch for tag-related errors (they should be bypassed)"
echo "4. Monitor logs: ./monitor-tag-errors.sh"
echo
echo -e "${YELLOW}To unlock tags later: ./unlock-subnet-tags.sh $TFVARS_FILE${NC}"
echo
