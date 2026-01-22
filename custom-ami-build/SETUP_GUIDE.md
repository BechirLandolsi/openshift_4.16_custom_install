# Quick Setup Guide - Prerequisites

Before running `create-custom-ami.sh`, complete these setup steps.

## Step 1: Check AWS CLI

```bash
aws --version
aws sts get-caller-identity  # Verify credentials work
```

## Step 2: Create or Find KMS Key

### Option A: Use Existing Key
```bash
# List your KMS keys
aws kms list-aliases --region eu-west-1

# Get ARN of existing key
aws kms describe-key \
  --key-id alias/your-key-name \
  --region eu-west-1 \
  --query 'KeyMetadata.Arn' \
  --output text
```

### Option B: Create New Key
```bash
# Create KMS key
aws kms create-key \
  --description "OpenShift 4.16 EBS Encryption" \
  --region eu-west-1

# Save the KeyId from output, then create alias
aws kms create-alias \
  --alias-name alias/openshift-416 \
  --target-key-id YOUR_KEY_ID \
  --region eu-west-1
```

## Step 3: Create vmimport IAM Role (One-Time)

```bash
# Check if already exists
aws iam get-role --role-name vmimport 2>/dev/null

# If not found, create it:

# 1. Trust policy
cat > trust-policy.json <<'TRUST'
{
   "Version": "2012-10-17",
   "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "vmie.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
         "StringEquals":{"sts:Externalid": "vmimport"}
      }
   }]
}
TRUST

# 2. Create role
aws iam create-role \
  --role-name vmimport \
  --assume-role-policy-document file://trust-policy.json

# 3. Role policy
cat > role-policy.json <<'POLICY'
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect": "Allow",
         "Action": ["s3:GetBucketLocation","s3:GetObject","s3:ListBucket"],
         "Resource": ["arn:aws:s3:::*","arn:aws:s3:::*/*"]
      },
      {
         "Effect": "Allow",
         "Action": ["ec2:ModifySnapshotAttribute","ec2:CopySnapshot","ec2:RegisterImage","ec2:Describe*","ec2:ImportSnapshot","ec2:DescribeImportSnapshotTasks"],
         "Resource": "*"
      },
      {
         "Effect": "Allow",
         "Action": ["kms:CreateGrant","kms:Decrypt","kms:DescribeKey","kms:Encrypt","kms:GenerateDataKey*","kms:ReEncrypt*"],
         "Resource": "*"
      }
   ]
}
POLICY

# 4. Attach policy
aws iam put-role-policy \
  --role-name vmimport \
  --policy-name vmimport \
  --policy-document file://role-policy.json

# 5. Verify
aws iam get-role --role-name vmimport

echo "✓ vmimport role created"
```

## Step 4: Grant vmimport Access to KMS Key

```bash
# Get your account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Set your KMS key (if not already set)
export KMS_KEY_ID="alias/openshift-416"  # or ARN
export AWS_REGION="eu-west-1"

# Create KMS grant for vmimport role
aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmimport" \
  --operations "Encrypt" "Decrypt" "ReEncryptFrom" "ReEncryptTo" "GenerateDataKey" "GenerateDataKeyWithoutPlaintext" "DescribeKey" "CreateGrant" \
  --region "$AWS_REGION"

# Verify grant
aws kms list-grants --key-id "$KMS_KEY_ID" --region "$AWS_REGION"

echo "✓ KMS grant created"
```

## Step 5: Set Environment Variables

```bash
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="alias/openshift-416"  # or full ARN
```

## Step 6: Run AMI Creation Script

```bash
chmod +x create-custom-ami.sh
./create-custom-ami.sh
```

## Common Errors and Solutions

### Error: Permission denied
```bash
chmod +x create-custom-ami.sh
```

### Error: vmimport role does not exist or insufficient permissions
**Solutions**:
- Create role: Run Step 3 above
- Update role permissions: Add `ec2:ImportSnapshot` and `ec2:DescribeImportSnapshotTasks`
- Grant KMS access: Run Step 4 above

### Error: KMS_KEY_ID not set
```bash
export KMS_KEY_ID="alias/your-key-name"
```

### Error: KMS permission denied
```bash
# Verify key exists and you have access
aws kms describe-key --key-id "$KMS_KEY_ID" --region "$AWS_REGION"
```

## Complete Example

```bash
# Prerequisites
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"

# Create KMS key (if needed)
KMS_KEY_ID=$(aws kms create-key \
  --description "OpenShift EBS" \
  --region $AWS_REGION \
  --query 'KeyMetadata.KeyId' \
  --output text)

aws kms create-alias \
  --alias-name alias/ocp-demo \
  --target-key-id $KMS_KEY_ID \
  --region $AWS_REGION

export KMS_KEY_ID="alias/ocp-demo"

# Create vmimport role (if needed) - see Step 3 above

# Run AMI creation
./create-custom-ami.sh

# Result saved in:
source custom-ami-result.env
echo "AMI: $CUSTOM_AMI"
```

---

For full documentation, see `README.md` in this directory.
