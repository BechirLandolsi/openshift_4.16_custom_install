#!/bin/bash
# Script to create KMS key for OpenShift EBS encryption
# This key will be used for:
# - Custom AMI encryption
# - EC2 root volumes (inherited from AMI)
# - Persistent volumes (PVCs via CSI driver)

set -euo pipefail

# Configuration variables
REGION="${AWS_REGION:-eu-west-3}"
KEY_ALIAS="${KMS_KEY_ALIAS:-alias/openshift-ebs-encryption}"
KEY_DESCRIPTION="${KMS_KEY_DESCRIPTION:-OpenShift 4.16 EBS Encryption Key}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}KMS Key Creation for OpenShift${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Configuration:"
echo "  Region: $REGION"
echo "  Key Alias: $KEY_ALIAS"
echo "  Description: $KEY_DESCRIPTION"
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo ""

# Check if key alias already exists
echo -e "${YELLOW}Checking if KMS key alias already exists...${NC}"
EXISTING_KEY=$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='$KEY_ALIAS'].TargetKeyId" --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_KEY" ]; then
    echo -e "${BLUE}KMS key alias '$KEY_ALIAS' already exists${NC}"
    echo "Key ID: $EXISTING_KEY"
    
    # Get key ARN
    KEY_ARN=$(aws kms describe-key --key-id "$EXISTING_KEY" --region "$REGION" --query 'KeyMetadata.Arn' --output text)
    echo "Key ARN: $KEY_ARN"
    
    # Check key state
    KEY_STATE=$(aws kms describe-key --key-id "$EXISTING_KEY" --region "$REGION" --query 'KeyMetadata.KeyState' --output text)
    echo "Key State: $KEY_STATE"
    
    if [ "$KEY_STATE" != "Enabled" ]; then
        echo -e "${RED}Warning: Key is not enabled. Current state: $KEY_STATE${NC}"
        echo "Please enable the key or create a new one."
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}Using existing KMS key.${NC}"
    
else
    # Create new KMS key
    echo -e "${YELLOW}Creating new KMS key...${NC}"
    
    # Create the key with bootstrap policy
    KEY_RESPONSE=$(aws kms create-key \
        --description "$KEY_DESCRIPTION" \
        --key-usage ENCRYPT_DECRYPT \
        --origin AWS_KMS \
        --region "$REGION" \
        --policy file://kms-bootstrap-policy.json 2>/dev/null || \
        aws kms create-key \
        --description "$KEY_DESCRIPTION" \
        --key-usage ENCRYPT_DECRYPT \
        --origin AWS_KMS \
        --region "$REGION")
    
    EXISTING_KEY=$(echo "$KEY_RESPONSE" | jq -r '.KeyMetadata.KeyId')
    KEY_ARN=$(echo "$KEY_RESPONSE" | jq -r '.KeyMetadata.Arn')
    
    echo -e "${GREEN}✓ KMS key created${NC}"
    echo "Key ID: $EXISTING_KEY"
    echo "Key ARN: $KEY_ARN"
    
    # Create alias
    echo -e "${YELLOW}Creating key alias...${NC}"
    aws kms create-alias \
        --alias-name "$KEY_ALIAS" \
        --target-key-id "$EXISTING_KEY" \
        --region "$REGION"
    echo -e "${GREEN}✓ Alias created: $KEY_ALIAS${NC}"
fi

# Apply bootstrap policy to ensure root account has access
echo ""
echo -e "${YELLOW}Applying bootstrap KMS policy...${NC}"

# Check if bootstrap policy file exists, if not create it
if [ ! -f "kms-bootstrap-policy.json" ]; then
    echo "Creating kms-bootstrap-policy.json..."
    cat > kms-bootstrap-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Id": "openshift-ebs-encryption-bootstrap-policy",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
EOF
    echo -e "${GREEN}✓ Bootstrap policy file created${NC}"
fi

# Apply the bootstrap policy
aws kms put-key-policy \
    --key-id "$EXISTING_KEY" \
    --policy-name default \
    --policy file://kms-bootstrap-policy.json \
    --region "$REGION"
echo -e "${GREEN}✓ Bootstrap policy applied${NC}"

# Grant vmimport role access (for AMI creation)
echo ""
echo -e "${YELLOW}Granting vmimport role access to KMS key...${NC}"

# Check if vmimport role exists
if aws iam get-role --role-name vmimport >/dev/null 2>&1; then
    # Create grant for vmimport
    aws kms create-grant \
        --key-id "$EXISTING_KEY" \
        --grantee-principal "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmimport" \
        --operations "Encrypt" "Decrypt" "ReEncryptFrom" "ReEncryptTo" "GenerateDataKey" "GenerateDataKeyWithoutPlaintext" "DescribeKey" "CreateGrant" \
        --region "$REGION" >/dev/null 2>&1 || echo "Grant may already exist"
    echo -e "${GREEN}✓ vmimport role granted access${NC}"
else
    echo -e "${YELLOW}⚠ vmimport role not found. Create it before running AMI import.${NC}"
    echo "  See README.md for vmimport role creation instructions."
fi

# Save results
echo ""
echo -e "${YELLOW}Saving results...${NC}"
cat > kms-key-result.env <<EOF
# KMS Key for OpenShift EBS Encryption
# Created: $(date)
export KMS_KEY_ID="${EXISTING_KEY}"
export KMS_KEY_ARN="${KEY_ARN}"
export KMS_KEY_ALIAS="${KEY_ALIAS}"
export AWS_REGION="${REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF

echo -e "${GREEN}✓ Results saved to kms-key-result.env${NC}"

# Summary
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}KMS Key Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "KMS Key Details:"
echo "  Key ID:    $EXISTING_KEY"
echo "  Key ARN:   $KEY_ARN"
echo "  Alias:     $KEY_ALIAS"
echo "  Region:    $REGION"
echo ""
echo "Next steps:"
echo "1. Create custom AMI encrypted with this key:"
echo "   source kms-key-result.env"
echo "   ./create-custom-ami.sh"
echo ""
echo "2. Update terraform tfvars with:"
echo "   kms_ec2_alias = \"$KEY_ALIAS\""
echo ""
echo "3. The Terraform will automatically update the KMS policy"
echo "   to include OpenShift IAM roles (control plane, worker,"
echo "   Machine API, CSI driver)."
echo ""
echo -e "${BLUE}Note: The bootstrap policy allows only the root account.${NC}"
echo -e "${BLUE}Terraform will update it with role-specific permissions.${NC}"
echo ""
