#!/bin/bash
# Script to verify custom RHCOS AMI encryption status and KMS key configuration
# This script checks if the AMI is properly encrypted with the customer-managed KMS key (CMK)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration - can be overridden by environment variables or command line
AMI_ID="${AMI_ID:-}"
EXPECTED_KMS_KEY="${EXPECTED_KMS_KEY:-}"
REGION="${AWS_REGION:-eu-west-3}"

# Try to source from result files if not set
if [ -z "$AMI_ID" ] && [ -f "custom-ami-result.env" ]; then
    source custom-ami-result.env
    AMI_ID="${CUSTOM_AMI:-}"
    EXPECTED_KMS_KEY="${KMS_KEY_ID:-$EXPECTED_KMS_KEY}"
fi

if [ -z "$EXPECTED_KMS_KEY" ] && [ -f "kms-key-result.env" ]; then
    source kms-key-result.env
    EXPECTED_KMS_KEY="${KMS_KEY_ARN:-$EXPECTED_KMS_KEY}"
fi

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Verify that a custom RHCOS AMI is properly encrypted with your KMS CMK."
    echo ""
    echo "Options:"
    echo "  -a, --ami AMI_ID           AMI ID to verify (e.g., ami-0123456789abcdef0)"
    echo "  -k, --kms KMS_KEY          Expected KMS key ARN or alias"
    echo "  -r, --region REGION        AWS region (default: eu-west-3)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  AMI_ID                     AMI ID to verify"
    echo "  EXPECTED_KMS_KEY           Expected KMS key ARN or alias"
    echo "  AWS_REGION                 AWS region"
    echo ""
    echo "Examples:"
    echo "  # Using environment files (auto-detected):"
    echo "  ./verify-ami-encryption.sh"
    echo ""
    echo "  # Using command line arguments:"
    echo "  ./verify-ami-encryption.sh -a ami-0123456789abcdef0 -k alias/openshift-ebs-encryption"
    echo ""
    echo "  # Using environment variables:"
    echo "  export AMI_ID=ami-0123456789abcdef0"
    echo "  export EXPECTED_KMS_KEY=arn:aws:kms:eu-west-3:123456789012:key/..."
    echo "  ./verify-ami-encryption.sh"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--ami)
            AMI_ID="$2"
            shift 2
            ;;
        -k|--kms)
            EXPECTED_KMS_KEY="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$AMI_ID" ]; then
    echo -e "${RED}ERROR: AMI_ID is required${NC}"
    echo ""
    echo "Please provide an AMI ID using one of these methods:"
    echo "  1. Command line: ./verify-ami-encryption.sh -a ami-0123456789abcdef0"
    echo "  2. Environment:  export AMI_ID=ami-0123456789abcdef0"
    echo "  3. Auto-detect:  Ensure custom-ami-result.env exists"
    echo ""
    usage
fi

# Function to resolve KMS alias to ARN
resolve_kms_key() {
    local key_input="$1"
    local resolved_arn=""
    
    if [[ "$key_input" == alias/* ]]; then
        # It's an alias, resolve to ARN
        resolved_arn=$(aws kms describe-key \
            --region "$REGION" \
            --key-id "$key_input" \
            --query 'KeyMetadata.Arn' \
            --output text 2>/dev/null || echo "")
    elif [[ "$key_input" == arn:aws:kms:* ]]; then
        # It's already an ARN
        resolved_arn="$key_input"
    else
        # It might be a key ID, try to get the ARN
        resolved_arn=$(aws kms describe-key \
            --region "$REGION" \
            --key-id "$key_input" \
            --query 'KeyMetadata.Arn' \
            --output text 2>/dev/null || echo "")
    fi
    
    echo "$resolved_arn"
}

# Function to get KMS key alias from ARN
get_kms_alias() {
    local key_arn="$1"
    local key_id=""
    
    # Extract key ID from ARN
    key_id=$(echo "$key_arn" | sed 's/.*key\///')
    
    # Get alias for this key
    aws kms list-aliases \
        --region "$REGION" \
        --key-id "$key_id" \
        --query 'Aliases[0].AliasName' \
        --output text 2>/dev/null || echo "No alias"
}

# Function to check if key is AWS managed or customer managed
get_kms_key_type() {
    local key_arn="$1"
    local key_manager=""
    
    key_manager=$(aws kms describe-key \
        --region "$REGION" \
        --key-id "$key_arn" \
        --query 'KeyMetadata.KeyManager' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$key_manager" = "AWS" ]; then
        echo "AWS Managed"
    elif [ "$key_manager" = "CUSTOMER" ]; then
        echo "Customer Managed (CMK)"
    else
        echo "$key_manager"
    fi
}

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}AMI Encryption Verification Tool${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  AMI ID:           $AMI_ID"
echo "  Region:           $REGION"
echo "  Expected KMS Key: ${EXPECTED_KMS_KEY:-Not specified (will only report actual key)}"
echo ""

# Step 1: Verify AMI exists
echo -e "${YELLOW}Step 1: Checking AMI status...${NC}"
AMI_INFO=$(aws ec2 describe-images \
    --region "$REGION" \
    --image-ids "$AMI_ID" \
    --query 'Images[0]' \
    --output json 2>/dev/null || echo "null")

if [ "$AMI_INFO" = "null" ] || [ -z "$AMI_INFO" ]; then
    echo -e "${RED}✗ ERROR: AMI $AMI_ID not found in region $REGION${NC}"
    exit 1
fi

AMI_NAME=$(echo "$AMI_INFO" | jq -r '.Name // "N/A"')
AMI_STATE=$(echo "$AMI_INFO" | jq -r '.State // "N/A"')
AMI_CREATION=$(echo "$AMI_INFO" | jq -r '.CreationDate // "N/A"')
AMI_DESCRIPTION=$(echo "$AMI_INFO" | jq -r '.Description // "N/A"')

echo -e "${GREEN}✓ AMI found${NC}"
echo ""
echo -e "${BLUE}AMI Details:${NC}"
echo "  Name:         $AMI_NAME"
echo "  State:        $AMI_STATE"
echo "  Created:      $AMI_CREATION"
echo "  Description:  $AMI_DESCRIPTION"
echo ""

# Step 2: Get snapshot information
echo -e "${YELLOW}Step 2: Checking root volume snapshot...${NC}"
SNAPSHOT_ID=$(echo "$AMI_INFO" | jq -r '.BlockDeviceMappings[0].Ebs.SnapshotId // "N/A"')
VOLUME_SIZE=$(echo "$AMI_INFO" | jq -r '.BlockDeviceMappings[0].Ebs.VolumeSize // "N/A"')
VOLUME_TYPE=$(echo "$AMI_INFO" | jq -r '.BlockDeviceMappings[0].Ebs.VolumeType // "N/A"')
DEVICE_NAME=$(echo "$AMI_INFO" | jq -r '.BlockDeviceMappings[0].DeviceName // "N/A"')

if [ "$SNAPSHOT_ID" = "N/A" ] || [ -z "$SNAPSHOT_ID" ]; then
    echo -e "${RED}✗ ERROR: Could not find snapshot for AMI${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Snapshot found: $SNAPSHOT_ID${NC}"
echo ""
echo -e "${BLUE}Block Device Mapping:${NC}"
echo "  Device:       $DEVICE_NAME"
echo "  Snapshot ID:  $SNAPSHOT_ID"
echo "  Volume Size:  ${VOLUME_SIZE} GB"
echo "  Volume Type:  $VOLUME_TYPE"
echo ""

# Step 3: Check snapshot encryption
echo -e "${YELLOW}Step 3: Verifying snapshot encryption...${NC}"
SNAPSHOT_INFO=$(aws ec2 describe-snapshots \
    --region "$REGION" \
    --snapshot-ids "$SNAPSHOT_ID" \
    --query 'Snapshots[0]' \
    --output json 2>/dev/null || echo "null")

if [ "$SNAPSHOT_INFO" = "null" ] || [ -z "$SNAPSHOT_INFO" ]; then
    echo -e "${RED}✗ ERROR: Could not retrieve snapshot information${NC}"
    exit 1
fi

SNAPSHOT_ENCRYPTED=$(echo "$SNAPSHOT_INFO" | jq -r '.Encrypted // false')
ACTUAL_KMS_KEY=$(echo "$SNAPSHOT_INFO" | jq -r '.KmsKeyId // "None"')
SNAPSHOT_STATE=$(echo "$SNAPSHOT_INFO" | jq -r '.State // "N/A"')

echo ""
echo -e "${BLUE}Snapshot Encryption Status:${NC}"
echo "  Snapshot ID:  $SNAPSHOT_ID"
echo "  State:        $SNAPSHOT_STATE"
echo "  Encrypted:    $SNAPSHOT_ENCRYPTED"
echo "  KMS Key ARN:  $ACTUAL_KMS_KEY"

if [ "$SNAPSHOT_ENCRYPTED" = "true" ]; then
    echo -e "  Status:       ${GREEN}✓ ENCRYPTED${NC}"
else
    echo -e "  Status:       ${RED}✗ NOT ENCRYPTED${NC}"
    echo ""
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}VERIFICATION FAILED${NC}"
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}The AMI snapshot is NOT encrypted!${NC}"
    exit 1
fi

# Step 4: Get KMS key details
echo ""
echo -e "${YELLOW}Step 4: Retrieving KMS key details...${NC}"

if [ "$ACTUAL_KMS_KEY" != "None" ] && [ -n "$ACTUAL_KMS_KEY" ]; then
    KMS_ALIAS=$(get_kms_alias "$ACTUAL_KMS_KEY")
    KMS_TYPE=$(get_kms_key_type "$ACTUAL_KMS_KEY")
    
    # Get additional KMS key info
    KMS_KEY_INFO=$(aws kms describe-key \
        --region "$REGION" \
        --key-id "$ACTUAL_KMS_KEY" \
        --query 'KeyMetadata' \
        --output json 2>/dev/null || echo "{}")
    
    KMS_KEY_ID=$(echo "$KMS_KEY_INFO" | jq -r '.KeyId // "N/A"')
    KMS_KEY_STATE=$(echo "$KMS_KEY_INFO" | jq -r '.KeyState // "N/A"')
    KMS_KEY_USAGE=$(echo "$KMS_KEY_INFO" | jq -r '.KeyUsage // "N/A"')
    KMS_CREATION_DATE=$(echo "$KMS_KEY_INFO" | jq -r '.CreationDate // "N/A"')
    KMS_DESCRIPTION=$(echo "$KMS_KEY_INFO" | jq -r '.Description // "N/A"')
    
    echo ""
    echo -e "${BLUE}KMS Key Details:${NC}"
    echo "  Key ID:       $KMS_KEY_ID"
    echo "  Key ARN:      $ACTUAL_KMS_KEY"
    echo "  Alias:        $KMS_ALIAS"
    echo "  Type:         $KMS_TYPE"
    echo "  State:        $KMS_KEY_STATE"
    echo "  Usage:        $KMS_KEY_USAGE"
    echo "  Created:      $KMS_CREATION_DATE"
    echo "  Description:  $KMS_DESCRIPTION"
    
    # Check if it's a customer managed key
    if [ "$KMS_TYPE" = "Customer Managed (CMK)" ]; then
        echo -e "  CMK Status:   ${GREEN}✓ Customer Managed Key${NC}"
    else
        echo -e "  CMK Status:   ${YELLOW}⚠ AWS Managed Key (not CMK)${NC}"
    fi
else
    echo -e "${RED}✗ Could not retrieve KMS key information${NC}"
fi

# Step 5: Compare with expected KMS key (if provided)
echo ""
echo -e "${YELLOW}Step 5: KMS key verification...${NC}"

VERIFICATION_PASSED=true

if [ -n "$EXPECTED_KMS_KEY" ]; then
    # Resolve expected key to ARN for comparison
    EXPECTED_KMS_ARN=$(resolve_kms_key "$EXPECTED_KMS_KEY")
    
    if [ -z "$EXPECTED_KMS_ARN" ]; then
        echo -e "${YELLOW}⚠ WARNING: Could not resolve expected KMS key: $EXPECTED_KMS_KEY${NC}"
        echo "  Skipping key comparison."
    else
        echo ""
        echo -e "${BLUE}KMS Key Comparison:${NC}"
        echo "  Expected Key: $EXPECTED_KMS_ARN"
        echo "  Actual Key:   $ACTUAL_KMS_KEY"
        
        if [ "$ACTUAL_KMS_KEY" = "$EXPECTED_KMS_ARN" ]; then
            echo -e "  Match:        ${GREEN}✓ KEYS MATCH${NC}"
        else
            echo -e "  Match:        ${RED}✗ KEYS DO NOT MATCH${NC}"
            VERIFICATION_PASSED=false
        fi
    fi
else
    echo "  No expected KMS key specified - skipping comparison."
    echo "  To verify against a specific key, use: -k <kms-key-arn-or-alias>"
fi

# Step 6: Check AMI tags
echo ""
echo -e "${YELLOW}Step 6: Checking AMI tags...${NC}"
AMI_TAGS=$(echo "$AMI_INFO" | jq -r '.Tags // []')
TAG_COUNT=$(echo "$AMI_TAGS" | jq 'length')

if [ "$TAG_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${BLUE}AMI Tags:${NC}"
    echo "$AMI_TAGS" | jq -r '.[] | "  \(.Key): \(.Value)"'
else
    echo "  No tags found on AMI"
fi

# Final Summary
echo ""
echo -e "${CYAN}======================================${NC}"
if [ "$VERIFICATION_PASSED" = true ] && [ "$SNAPSHOT_ENCRYPTED" = "true" ]; then
    echo -e "${GREEN}VERIFICATION SUCCESSFUL${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
    echo -e "${GREEN}Summary:${NC}"
    echo "  ✓ AMI exists and is available"
    echo "  ✓ Snapshot is encrypted"
    if [ "$KMS_TYPE" = "Customer Managed (CMK)" ]; then
        echo "  ✓ Using Customer Managed Key (CMK)"
    else
        echo "  ⚠ Using AWS Managed Key (not CMK)"
    fi
    if [ -n "$EXPECTED_KMS_KEY" ] && [ -n "$EXPECTED_KMS_ARN" ]; then
        echo "  ✓ KMS key matches expected key"
    fi
    echo ""
    echo -e "${BLUE}AMI Ready for OpenShift Deployment:${NC}"
    echo "  AMI ID:     $AMI_ID"
    echo "  Region:     $REGION"
    echo "  KMS Key:    $ACTUAL_KMS_KEY"
    echo "  KMS Alias:  $KMS_ALIAS"
else
    echo -e "${RED}VERIFICATION FAILED${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
    echo -e "${RED}Issues detected:${NC}"
    if [ "$SNAPSHOT_ENCRYPTED" != "true" ]; then
        echo "  ✗ Snapshot is not encrypted"
    fi
    if [ "$VERIFICATION_PASSED" != true ]; then
        echo "  ✗ KMS key does not match expected key"
    fi
    echo ""
    echo "Please review the AMI configuration and ensure it was created"
    echo "with the correct KMS key using create-custom-ami.sh"
    exit 1
fi

echo ""
echo -e "${BLUE}Next steps for OpenShift deployment:${NC}"
echo "  1. Use this AMI ID in your terraform.tfvars:"
echo "     ami = \"$AMI_ID\""
echo ""
echo "  2. The AMI is pre-encrypted - no need to specify kmsKeyARN"
echo "     in install-config.yaml"
echo ""
