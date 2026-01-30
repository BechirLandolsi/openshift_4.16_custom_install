#!/bin/bash
# ==============================================================================
# Pre-Install Check Script
# ==============================================================================
# Run this BEFORE terraform apply to check for conflicting resources.
# This script only CHECKS and LISTS resources - it does NOT delete anything.
# If conflicts are found, delete them manually before running terraform apply.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
TFVARS_FILE="${1:-env/demo.tfvars}"
if [[ ! -f "$TFVARS_FILE" ]]; then
    echo -e "${RED}Error: $TFVARS_FILE not found${NC}"
    exit 1
fi

echo -e "${CYAN}Loading configuration from: ${TFVARS_FILE}${NC}"
CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
INFRA_RANDOM_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
DOMAIN=$(grep '^domain' "$TFVARS_FILE" | awk -F'"' '{print $2}')
HOSTED_ZONE=$(grep '^hosted_zone' "$TFVARS_FILE" | awk -F'"' '{print $2}')

INFRA_ID="${CLUSTER_NAME}-${INFRA_RANDOM_ID}"
BUCKET_NAME="${INFRA_ID}-terraform-remote-state-storage-s3"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Pre-Install Check (Read-Only)                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Infra ID:     $INFRA_ID"
echo "  Domain:       $DOMAIN"
echo "  Region:       $REGION"
echo

# Track conflicts
CONFLICTS_FOUND=0
CONFLICT_LIST=""

add_conflict() {
    ((CONFLICTS_FOUND++))
    CONFLICT_LIST="${CONFLICT_LIST}\n  $1"
}

# ==============================================================================
# 1. Check DNS records (*.apps wildcard)
# ==============================================================================
echo -e "${YELLOW}Checking DNS records...${NC}"

RECORD_NAME="*.apps.${CLUSTER_NAME}.${DOMAIN}."

# Find private zone
PRIVATE_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Config.PrivateZone==\`true\` && Name=='${DOMAIN}.'].Id" \
    --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')

if [[ -n "$PRIVATE_ZONE_ID" ]] && [[ "$PRIVATE_ZONE_ID" != "None" ]]; then
    RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$PRIVATE_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${RECORD_NAME}']" \
        --output json 2>/dev/null)
    
    if [[ "$RECORD" != "[]" ]] && [[ -n "$RECORD" ]]; then
        TYPE=$(echo "$RECORD" | jq -r '.[0].Type')
        echo -e "  ${RED}✗ FOUND: ${RECORD_NAME} (${TYPE}) in private zone ${PRIVATE_ZONE_ID}${NC}"
        add_conflict "DNS: ${RECORD_NAME} in private zone ${PRIVATE_ZONE_ID}"
    else
        echo -e "  ${GREEN}✓ No *.apps record in private zone${NC}"
    fi
fi

# Check public zone
if [[ -n "$HOSTED_ZONE" ]]; then
    RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE" \
        --query "ResourceRecordSets[?Name=='${RECORD_NAME}']" \
        --output json 2>/dev/null)
    
    if [[ "$RECORD" != "[]" ]] && [[ -n "$RECORD" ]]; then
        TYPE=$(echo "$RECORD" | jq -r '.[0].Type')
        echo -e "  ${RED}✗ FOUND: ${RECORD_NAME} (${TYPE}) in public zone ${HOSTED_ZONE}${NC}"
        add_conflict "DNS: ${RECORD_NAME} in public zone ${HOSTED_ZONE}"
    else
        echo -e "  ${GREEN}✓ No *.apps record in public zone${NC}"
    fi
fi

# ==============================================================================
# 2. Check S3 bucket
# ==============================================================================
echo
echo -e "${YELLOW}Checking S3 bucket...${NC}"

if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null >/dev/null; then
    echo -e "  ${RED}✗ FOUND: S3 bucket ${BUCKET_NAME}${NC}"
    add_conflict "S3: ${BUCKET_NAME}"
else
    echo -e "  ${GREEN}✓ S3 bucket does not exist${NC}"
fi

# ==============================================================================
# 3. Check DynamoDB table
# ==============================================================================
echo
echo -e "${YELLOW}Checking DynamoDB table...${NC}"

TABLE_NAME="${CLUSTER_NAME}-terraform-locks"
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null >/dev/null; then
    echo -e "  ${RED}✗ FOUND: DynamoDB table ${TABLE_NAME}${NC}"
    add_conflict "DynamoDB: ${TABLE_NAME}"
else
    echo -e "  ${GREEN}✓ DynamoDB table does not exist${NC}"
fi

# ==============================================================================
# 4. Check KMS alias
# ==============================================================================
echo
echo -e "${YELLOW}Checking KMS alias...${NC}"

KMS_ALIAS="alias/s3-terraform-state-${CLUSTER_NAME}"
if aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" 2>/dev/null >/dev/null; then
    echo -e "  ${RED}✗ FOUND: KMS alias ${KMS_ALIAS}${NC}"
    add_conflict "KMS: ${KMS_ALIAS}"
else
    echo -e "  ${GREEN}✓ KMS alias does not exist${NC}"
fi

# ==============================================================================
# 5. Check local files
# ==============================================================================
echo
echo -e "${YELLOW}Checking local files...${NC}"

if [[ -d "installer-files" ]]; then
    echo -e "  ${YELLOW}⚠ FOUND: installer-files/ directory${NC}"
    add_conflict "Local: installer-files/"
else
    echo -e "  ${GREEN}✓ No installer-files directory${NC}"
fi

if [[ -f "terraform.tfstate" ]]; then
    echo -e "  ${YELLOW}⚠ FOUND: terraform.tfstate file${NC}"
    add_conflict "Local: terraform.tfstate"
else
    echo -e "  ${GREEN}✓ No terraform.tfstate file${NC}"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo

if [[ $CONFLICTS_FOUND -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ No conflicts found - Ready for fresh install!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "You can now run:"
    echo "  terraform init"
    echo "  terraform apply -var-file=$TFVARS_FILE"
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ ${CONFLICTS_FOUND} conflict(s) found - Delete before install            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Resources to delete:${NC}"
    echo -e "$CONFLICT_LIST"
    echo
    echo -e "${YELLOW}Commands to delete (run manually if needed):${NC}"
    echo
    
    # Print delete commands
    if [[ -n "$PRIVATE_ZONE_ID" ]]; then
        echo "# Delete DNS from private zone"
        echo "# (Get exact record details first, then delete)"
    fi
    
    if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null >/dev/null; then
        echo "aws s3 rb s3://${BUCKET_NAME} --force --region $REGION"
    fi
    
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null >/dev/null; then
        echo "aws dynamodb delete-table --table-name ${TABLE_NAME} --region $REGION"
    fi
    
    if aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" 2>/dev/null >/dev/null; then
        echo "aws kms delete-alias --alias-name ${KMS_ALIAS} --region $REGION"
    fi
    
    if [[ -d "installer-files" ]]; then
        echo "rm -rf installer-files/"
    fi
    
    if [[ -f "terraform.tfstate" ]]; then
        echo "rm -f terraform.tfstate terraform.tfstate.backup"
    fi
    
    echo
fi
