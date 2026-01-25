# Custom RHCOS AMI Creation for OpenShift 4.16

This directory contains the **official Red Hat documented process** for creating a custom RHCOS AMI with KMS encryption for OpenShift 4.16 on AWS.

**Method**: VMDK import (Red Hat official supported method)  
**Reference**: [Red Hat OpenShift 4.16 Documentation - Custom RHCOS AMI Upload](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-upload-custom-rhcos-ami_installing-aws-secret-region)

## Why Pre-Encrypt the AMI?

**Critical**: When using KMS-encrypted EBS volumes with OpenShift, the AMI **must be encrypted with the same KMS key** you want to use for EC2 instances. If you try to launch an instance from an AMI encrypted with Key-A and specify Key-B in the MachineSet, AWS will terminate the instance with `InvalidKMSKey.InvalidState`.

### Benefits of Pre-Encrypted AMI

- ✅ **No key mismatch errors** - AMI encryption is inherited at launch
- ✅ **Simplified Terraform** - No need to specify `kmsKeyARN` in install-config
- ✅ **Red Hat support compatibility** - Official documented process
- ✅ **Consistent encryption** - All root volumes use the same CMK
- ✅ **Compliance ready** - Customer-managed keys for audit requirements

## Quick Start (Recommended Workflow)

```bash
# Step 1: Create KMS key (or use existing)
./create-kms-key.sh

# Step 2: Source the KMS key details
source kms-key-result.env

# Step 3: Create encrypted AMI
./create-custom-ami.sh

# Step 4: Source the AMI details
source custom-ami-result.env

# Step 5: Update Terraform tfvars with AMI ID and KMS alias
echo "ami = \"$CUSTOM_AMI\""
echo "kms_ec2_alias = \"$KMS_KEY_ALIAS\""
```

## Files in This Directory

| File | Description |
|------|-------------|
| `create-kms-key.sh` | Creates KMS key with bootstrap policy |
| `create-custom-ami.sh` | Creates RHCOS AMI encrypted with your KMS key |
| `kms-bootstrap-policy.json` | Template for initial KMS key policy |
| `kms-key-result.env` | Generated - KMS key details (after running create-kms-key.sh) |
| `custom-ami-result.env` | Generated - AMI details (after running create-custom-ami.sh) |
| `README.md` | This documentation |

## Quick Reference Commands

### Create KMS Key
```bash
# Option 1: Use the provided script (recommended)
./create-kms-key.sh

# Option 2: Manual creation
aws kms create-key --description "OpenShift EBS Encryption" --region eu-west-3
aws kms create-alias --alias-name alias/openshift-ebs-encryption --target-key-id <KEY_ID> --region eu-west-3
```

### Check vmimport Role
```bash
# Check if exists
aws iam get-role --role-name vmimport

# If missing, see Prerequisites section to create it
```

### Run AMI Creation
```bash
# After creating/sourcing KMS key
source kms-key-result.env
./create-custom-ami.sh
```

## Prerequisites

### Red Hat Official Documentation

This AMI creation process is based on the official Red Hat OpenShift documentation. Before proceeding, review these resources:

**Uploading a Custom RHCOS AMI to AWS**  
📖 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-upload-custom-rhcos-ami_installing-aws-secret-region

This documentation covers:
- Official procedure for VMDK import to create custom AMIs
- Requirements for RHCOS AMI compatibility
- KMS encryption configuration during AMI import
- AWS service role requirements (vmimport)
- Supported RHCOS versions for OpenShift 4.16

**Finding RHCOS Images**  
📖 https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-custom-ami_installing-aws-customizations

This documentation covers:
- Where to download RHCOS VMDK files
- Supported machine architecture (x86_64, aarch64)
- Version compatibility with OpenShift releases
- Image format requirements

### Customer Responsibilities

Before creating a custom AMI, ensure you have:

| Requirement | Description | Documentation Reference |
|-------------|-------------|------------------------|
| **AWS CLI** | Installed and configured with credentials | See below |
| **IAM Permissions** | EC2, KMS, S3, IAM permissions for AMI creation | See below |
| **vmimport Role** | AWS service role for importing VM images | Red Hat Official Doc |
| **KMS Key** | Customer-managed KMS key for EBS encryption | See below |
| **S3 Bucket** | Temporary bucket for VMDK upload (script creates) | Red Hat Official Doc |
| **RHCOS VMDK** | Official RHCOS image for OpenShift 4.16 | Red Hat Official Doc |
| **Network Access** | Ability to download from mirror.openshift.com | Red Hat Official Doc |

**⚠️ IMPORTANT**: This process creates the AMI with KMS encryption. IMDSv2 enforcement is configured at **instance launch time** in the OpenShift install-config.yaml and machine sets, not in the AMI itself.

---

### 1. AWS CLI Installed and Configured

```bash
# Verify AWS CLI is installed
aws --version

# Configure AWS credentials (if not already done)
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (e.g., eu-west-1)
# - Default output format (json)
```

### 2. IAM Permissions Required

Your AWS user/role needs:
- **EC2**: Create/manage AMIs and snapshots
- **EC2**: Import snapshots
- **KMS**: Use specified KMS key for encryption
- **S3**: Create bucket and upload files
- **IAM**: Create the vmimport role (one-time setup)

### 3. wget or curl

```bash
# Check if installed
wget --version
# or
curl --version
```

### 4. Create KMS Key (If You Don't Have One)

#### Option A: Find Existing KMS Key

```bash
# List all KMS keys in your region
aws kms list-keys --region eu-west-1

# List KMS key aliases (easier to read)
aws kms list-aliases --region eu-west-1

# Get details of a specific key
aws kms describe-key \
  --key-id alias/your-key-name \
  --region eu-west-1 \
  --query 'KeyMetadata.Arn' \
  --output text
```

#### Option B: Create New KMS Key

```bash
# Create a new KMS key
KMS_KEY_JSON=$(aws kms create-key \
  --description "OpenShift 4.16 EBS Encryption Key" \
  --region eu-west-1)

# Extract the Key ID
KMS_KEY_ID=$(echo $KMS_KEY_JSON | jq -r '.KeyMetadata.KeyId')
echo "KMS Key ID: $KMS_KEY_ID"

# Create an alias (optional but recommended)
aws kms create-alias \
  --alias-name alias/openshift-416 \
  --target-key-id $KMS_KEY_ID \
  --region eu-west-1

# Get the full ARN
KMS_KEY_ARN=$(aws kms describe-key \
  --key-id alias/openshift-416 \
  --region eu-west-1 \
  --query 'KeyMetadata.Arn' \
  --output text)

echo "KMS Key ARN: $KMS_KEY_ARN"

# Export for use in script
export KMS_KEY_ID="$KMS_KEY_ARN"
# Or use the alias:
# export KMS_KEY_ID="alias/openshift-416"
```

**What is KMS_KEY_ID?**

`KMS_KEY_ID` is your AWS KMS encryption key identifier, **NOT** your AWS access keys.

Formats accepted:
- **ARN**: `arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012`
- **Alias**: `alias/openshift-416`
- **Key ID**: `12345678-1234-1234-1234-123456789012`

### 5. Create vmimport IAM Role (Required - One-Time Setup)

The AWS VM import service requires a special IAM role named `vmimport`.

#### Check if vmimport role exists:

```bash
aws iam get-role --role-name vmimport 2>/dev/null

# If you get an error "NoSuchEntity", you need to create it
```

#### Create the vmimport role:

```bash
# Step 1: Create trust policy
cat > trust-policy.json <<'EOF'
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Principal": { "Service": "vmie.amazonaws.com" },
         "Action": "sts:AssumeRole",
         "Condition": {
            "StringEquals":{
               "sts:Externalid": "vmimport"
            }
         }
      }
   ]
}
EOF

# Step 2: Create the IAM role
aws iam create-role \
  --role-name vmimport \
  --assume-role-policy-document file://trust-policy.json

# Step 3: Create role permissions policy
cat > role-policy.json <<'EOF'
{
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect": "Allow",
         "Action": [
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket" 
         ],
         "Resource": [
            "arn:aws:s3:::*",
            "arn:aws:s3:::*/*"
         ]
      },
      {
         "Effect": "Allow",
         "Action": [
            "ec2:ModifySnapshotAttribute",
            "ec2:CopySnapshot",
            "ec2:RegisterImage",
            "ec2:Describe*",
            "ec2:ImportSnapshot",
            "ec2:DescribeImportSnapshotTasks"
         ],
         "Resource": "*"
      },
      {
         "Effect": "Allow",
         "Action": [
            "kms:CreateGrant",
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*"
         ],
         "Resource": "*"
      }
   ]
}
EOF

# Step 4: Attach policy to role
aws iam put-role-policy \
  --role-name vmimport \
  --policy-name vmimport \
  --policy-document file://role-policy.json

# Step 5: Verify role was created
aws iam get-role --role-name vmimport

echo "✓ vmimport role created successfully"
```

**Note**: This is a **one-time setup**. Once created, the `vmimport` role can be used for all future VMDK imports.

### 6. Grant vmimport Role Access to Your KMS Key

The vmimport role needs permission to use your KMS key for encryption:

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Grant vmimport role access to the KMS key
aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmimport" \
  --operations "Encrypt" "Decrypt" "ReEncryptFrom" "ReEncryptTo" "GenerateDataKey" "GenerateDataKeyWithoutPlaintext" "DescribeKey" "CreateGrant" \
  --region "$AWS_REGION"

# Verify the grant was created
aws kms list-grants --key-id "$KMS_KEY_ID" --region "$AWS_REGION"

echo "✓ KMS grant created for vmimport role"
```

**Important**: This grant allows the vmimport service to encrypt snapshots with your KMS key during the import process.

#### Common Error Without vmimport Role:

```
An error occurred (InvalidParameter) when calling the ImportSnapshot operation: 
The service role vmimport provided does not exist or does not have sufficient permissions.
```

**Solution**: Create the vmimport role using the commands above.

## Important: Understanding IMDSv2 Configuration

**Critical Clarification**: IMDSv2 (Instance Metadata Service v2) **cannot be configured in an AMI**. 

IMDSv2 is an **instance launch-time setting**, not an AMI property. You configure IMDSv2 enforcement in:

| Configuration File | Location | Parameter |
|-------------------|----------|-----------|
| **install-config.yaml** | Root level | `metadataService.authentication: Required` |
| **Machine Sets** | Terraform templates | `metadataServiceOptions.authentication: Required` |

Both custom and standard Red Hat AMIs require the same IMDSv2 configuration at launch time.

**What the Custom AMI Provides**:
- ✅ **KMS Encryption**: EBS volumes encrypted with your customer-managed key
- ✅ **Compliance**: Meets organizational security requirements
- ❌ **NOT IMDSv2**: This is configured separately (see above)

## Quick Start

### Before You Begin - Complete Prerequisites Checklist

```bash
# 1. Check AWS CLI is configured
aws sts get-caller-identity

# 2. Create or find KMS key
aws kms list-aliases --region eu-west-1
# OR create new: see "Create KMS Key" in Prerequisites section

# 3. Check if vmimport role exists
aws iam get-role --role-name vmimport 2>/dev/null
# If error, create it: see "Create vmimport IAM Role" in Prerequisites section

# 4. Grant vmimport access to KMS key
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..." # or alias/your-key

aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmimport" \
  --operations "Encrypt" "Decrypt" "ReEncryptFrom" "ReEncryptTo" "GenerateDataKey" "GenerateDataKeyWithoutPlaintext" "DescribeKey" "CreateGrant" \
  --region eu-west-1

# 5. Set environment variables
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
```

### Automated Method (Recommended)

Use the provided script:

```bash
# Make script executable (first time only)
chmod +x create-custom-ami.sh

# Run the creation script
./create-custom-ami.sh

# The script will:
# - Download RHCOS VMDK
# - Create S3 bucket
# - Upload VMDK to S3
# - Import as encrypted snapshot
# - Register custom AMI
# - Save AMI ID to custom-ami-result.env
```

Build time: ~30-40 minutes (mostly import snapshot time)

### Manual Method

Follow the step-by-step process below if you prefer manual control.

## Step-by-Step Manual Process

### Step 1: Set Environment Variables

```bash
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/your-key-id"
export S3_BUCKET_NAME="rhcos-import-${AWS_REGION}-$(date +%s)"
```

### Step 2: Download and Decompress RHCOS VMDK

```bash
# Download RHCOS VMDK for AWS (x86_64)
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/${RHCOS_VERSION}/rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

# Verify file size (~1GB compressed)
ls -lh rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

# Optional: Verify checksum
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/${RHCOS_VERSION}/sha256sum.txt
sha256sum -c sha256sum.txt --ignore-missing

# Decompress the VMDK file (AWS ImportSnapshot requires uncompressed)
gunzip -k rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

# Verify uncompressed file (~16GB)
ls -lh rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk
```

**Important**: AWS ImportSnapshot requires an **uncompressed VMDK file**. The `.vmdk.gz` file must be decompressed before upload.

### Step 3: Create S3 Bucket

```bash
# Create bucket (adjust for us-east-1 if needed)
if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION"
else
    aws s3api create-bucket \
      --bucket "$S3_BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "$S3_BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### Step 4: Upload Uncompressed VMDK to S3

```bash
# Upload uncompressed VMDK (takes 10-15 minutes for ~16GB file)
aws s3 cp rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk \
  s3://${S3_BUCKET_NAME}/ \
  --region "$AWS_REGION"

# Verify upload
aws s3 ls s3://${S3_BUCKET_NAME}/ --region "$AWS_REGION"

# Note: Must upload the .vmdk file (not .vmdk.gz)
```

### Step 5: Create Import Configuration

```bash
# Create containers.json
cat > containers.json <<EOF
{
  "Description": "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64",
  "Format": "vmdk",
  "UserBucket": {
    "S3Bucket": "${S3_BUCKET_NAME}",
    "S3Key": "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk"
  }
}
EOF
```

### Step 6: Import Snapshot with KMS Encryption

```bash
# Start import with KMS encryption
IMPORT_TASK_ID=$(aws ec2 import-snapshot \
  --region "$AWS_REGION" \
  --description "RHCOS ${RHCOS_VERSION} for OpenShift 4.16" \
  --disk-container "file://containers.json" \
  --encrypted \
  --kms-key-id "$KMS_KEY_ID" \
  --query 'ImportTaskId' \
  --output text)

echo "Import Task ID: $IMPORT_TASK_ID"

# Monitor progress (10-20 minutes)
watch -n 30 "aws ec2 describe-import-snapshot-tasks \
  --region $AWS_REGION \
  --import-task-ids $IMPORT_TASK_ID \
  --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.{Status:Status,Progress:Progress}'"

# Or check once:
aws ec2 describe-import-snapshot-tasks \
  --region "$AWS_REGION" \
  --import-task-ids "$IMPORT_TASK_ID"
```

Wait until `Status` = `completed`.

### Step 7: Get Snapshot ID

```bash
# Extract snapshot ID from completed import
SNAPSHOT_ID=$(aws ec2 describe-import-snapshot-tasks \
  --region "$AWS_REGION" \
  --import-task-ids "$IMPORT_TASK_ID" \
  --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' \
  --output text)

echo "Snapshot ID: $SNAPSHOT_ID"

# Verify encryption
aws ec2 describe-snapshots \
  --region "$AWS_REGION" \
  --snapshot-ids "$SNAPSHOT_ID" \
  --query 'Snapshots[0].[Encrypted,KmsKeyId]' \
  --output table

# Should show:
# | True | arn:aws:kms:eu-west-1:123456789012:key/... |
```

### Step 8: Register Custom AMI

```bash
# Create AMI from encrypted snapshot
CUSTOM_AMI=$(aws ec2 register-image \
  --region "$AWS_REGION" \
  --name "rhcos-${RHCOS_VERSION}-x86_64-ocp416-kms" \
  --description "RHCOS ${RHCOS_VERSION} for OpenShift 4.16 with KMS encryption" \
  --architecture x86_64 \
  --virtualization-type hvm \
  --root-device-name '/dev/xvda' \
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={DeleteOnTermination=true,SnapshotId=${SNAPSHOT_ID},VolumeType=gp3,VolumeSize=120}" \
  --ena-support \
  --query 'ImageId' \
  --output text)

echo "Custom AMI ID: $CUSTOM_AMI"
```

### Step 9: Tag Resources

```bash
# Tag AMI and snapshot
aws ec2 create-tags \
  --region "$AWS_REGION" \
  --resources "$CUSTOM_AMI" "$SNAPSHOT_ID" \
  --tags \
    Key=Name,Value="RHCOS ${RHCOS_VERSION} OpenShift 4.16 Custom" \
    Key=OS,Value=RHCOS \
    Key=OS-Version,Value="${RHCOS_VERSION}" \
    Key=OCP-Version,Value=4.16 \
    Key=Encrypted,Value=KMS \
    Key=Method,Value=VMDK-Import \
    Key=Compliance,Value=Required
```

### Step 10: Save Results

```bash
# Save AMI information
cat > custom-ami-result.env <<EOF
# Custom RHCOS AMI for OpenShift 4.16
# Created: $(date)
export CUSTOM_AMI="${CUSTOM_AMI}"
export AWS_REGION="${AWS_REGION}"
export RHCOS_VERSION="${RHCOS_VERSION}"
export SNAPSHOT_ID="${SNAPSHOT_ID}"
export KMS_KEY_ID="${KMS_KEY_ID}"
EOF

echo "Results saved to: custom-ami-result.env"
```

## Verification

After AMI creation, verify all properties:

```bash
# Source the results
source custom-ami-result.env

# Verify AMI exists and is available
aws ec2 describe-images \
  --region "$AWS_REGION" \
  --image-ids "$CUSTOM_AMI" \
  --query 'Images[0].[ImageId,Name,State,Architecture,EnaSupport]' \
  --output table

# Expected: State = available, Architecture = x86_64, EnaSupport = True

# Verify KMS encryption
aws ec2 describe-snapshots \
  --region "$AWS_REGION" \
  --snapshot-ids "$SNAPSHOT_ID" \
  --query 'Snapshots[0].[SnapshotId,Encrypted,KmsKeyId,VolumeSize]' \
  --output table

# Expected: Encrypted = True, KmsKeyId = your-kms-arn

# Check AMI block device mapping
aws ec2 describe-images \
  --region "$AWS_REGION" \
  --image-ids "$CUSTOM_AMI" \
  --query 'Images[0].BlockDeviceMappings[0].Ebs' \
  --output json

# Expected: Shows snapshot, encrypted, volume type
```

## Using the Custom AMI

### Update Terraform Variables

```hcl
# In terraform-openshift-v18/env/your-cluster.tfvars

# AMI ID (same for all node types)
ami               = "ami-0abcdef1234567890"  # Your custom AMI ID
aws_worker_iam_id = "ami-0abcdef1234567890"  # Same AMI ID

# KMS alias for policy management (Terraform updates the policy)
kms_ec2_alias = "alias/openshift-ebs-encryption"

# Additional roles for KMS policy (created by ccoctl)
kms_additional_role_arns = [
  "arn:aws:iam::123456789012:role/my-cluster-openshift-machine-api-aws-cloud-credentials",
  "arn:aws:iam::123456789012:role/my-cluster-openshift-cluster-csi-drivers-ebs-cloud-credentia"
]
```

### What You DON'T Need

Since the AMI is pre-encrypted with your CMK, you **do NOT** need to specify `kmsKeyARN` in:

- ❌ `install-config.yaml` - No `kmsKeyARN` needed for root volumes
- ❌ MachineSet templates - No `kmsKey` block needed

The encryption is automatically inherited from the AMI.

### What Terraform Still Manages

Even with a pre-encrypted AMI, Terraform still:

- ✅ Updates KMS key policy to grant `kms:CreateGrant` to IAM roles
- ✅ This is required because EC2 must create grants to decrypt volumes for new instances
- ✅ The Machine API and CSI driver roles need this permission

## Configuring IMDSv2 (Separate from AMI)

IMDSv2 is configured **at instance launch**, not in the AMI.

### In install-config.yaml:

```yaml
apiVersion: v1
baseDomain: example.com
controlPlane:
  platform:
    aws:
      metadataService:
        authentication: Required  # Enforces IMDSv2
compute:
- name: worker
  platform:
    aws:
      metadataService:
        authentication: Required  # Enforces IMDSv2
```

### In Terraform templates.tf:

The `install-config.yaml` template should include:

```yaml
compute:
- name: worker
  platform:
    aws:
      metadataService:
        authentication: Required
```

## Cleanup

### Delete S3 Bucket (After AMI Creation)

```bash
# Delete VMDK from S3
aws s3 rm s3://${S3_BUCKET_NAME}/rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk

# Delete bucket
aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION"

# Delete local files to save space
rm rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk  # ~16GB
# Keep compressed: rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz (~1GB)
```

### Delete AMI and Snapshot (To Start Over)

```bash
# Deregister AMI
aws ec2 deregister-image --region "$AWS_REGION" --image-id "$CUSTOM_AMI"

# Delete snapshot
aws ec2 delete-snapshot --region "$AWS_REGION" --snapshot-id "$SNAPSHOT_ID"
```

## Troubleshooting

### Issue: Permission Denied When Running Script

**Error**: `bash: ./create-custom-ami.sh: Permission denied`

**Solution**:
```bash
# Make script executable
chmod +x create-custom-ami.sh

# Then run it
./create-custom-ami.sh

# Or run directly with bash
bash create-custom-ami.sh
```

### Issue: vmimport Role Does Not Exist or Insufficient Permissions

**Error**: 
```
An error occurred (InvalidParameter) when calling the ImportSnapshot operation: 
The service role vmimport provided does not exist or does not have sufficient permissions.
```

**Possible Causes**:
1. vmimport role doesn't exist
2. vmimport role missing `ec2:ImportSnapshot` permission
3. vmimport role doesn't have access to your KMS key

**Solution A - Role Doesn't Exist**: Create the vmimport IAM role (see Prerequisites section above). Quick fix:

```bash
# Download helper script
cat > create-vmimport-role.sh <<'SCRIPT'
#!/bin/bash
echo "Creating vmimport IAM role..."

# Trust policy
cat > trust-policy.json <<'EOF'
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
EOF

# Create role
aws iam create-role \
  --role-name vmimport \
  --assume-role-policy-document file://trust-policy.json

# Role policy
cat > role-policy.json <<'EOF'
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
EOF

# Attach policy
aws iam put-role-policy \
  --role-name vmimport \
  --policy-name vmimport \
  --policy-document file://role-policy.json

echo "✓ vmimport role created"
aws iam get-role --role-name vmimport
SCRIPT

chmod +x create-vmimport-role.sh
./create-vmimport-role.sh
```

**Solution B - Role Missing ImportSnapshot Permission**: Update the existing role policy:

```bash
# Update vmimport role with correct permissions
cat > vmimport-policy-updated.json <<'POLICY'
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

aws iam put-role-policy \
  --role-name vmimport \
  --policy-name vmimport \
  --policy-document file://vmimport-policy-updated.json

echo "✓ vmimport role policy updated"
```

**Solution C - Role Doesn't Have KMS Access**: Grant vmimport access to your KMS key:

```bash
# Get your account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Grant vmimport role access to KMS key
aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmimport" \
  --operations "Encrypt" "Decrypt" "ReEncryptFrom" "ReEncryptTo" "GenerateDataKey" "GenerateDataKeyWithoutPlaintext" "DescribeKey" "CreateGrant" \
  --region "$AWS_REGION"

# Verify grant
aws kms list-grants --key-id "$KMS_KEY_ID" --region "$AWS_REGION"

echo "✓ KMS grant created for vmimport"
```

Then re-run `./create-custom-ami.sh`

### Issue: KMS_KEY_ID Not Set

**Error**: `ERROR: KMS_KEY_ID environment variable must be set`

**Solution**:
```bash
# Find existing KMS keys
aws kms list-aliases --region eu-west-1

# Use an existing key
export KMS_KEY_ID="alias/your-key-name"

# OR create a new key
aws kms create-key \
  --description "OpenShift EBS Encryption" \
  --region eu-west-1

# Then set the KMS_KEY_ID (use the KeyId from output)
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"
```

### Issue: Import Fails - KMS Permission Denied

**Error**: `Client.InvalidKmsKey.InvalidState` or permission denied

**Solution**:
```bash
# Verify KMS key exists and you have access
aws kms describe-key --key-id "$KMS_KEY_ID" --region "$AWS_REGION"

# Verify your IAM user/role has KMS permissions
aws iam get-user  # Get your user ARN

# Grant IAM user/role permission to use key
aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::123456789012:user/your-user" \
  --operations "Encrypt" "Decrypt" "GenerateDataKey" "DescribeKey" "CreateGrant"

# Or update KMS key policy to allow your user
```

### Issue: S3 Upload Slow

**Solution**:
- Use `aws s3 cp` with `--no-progress` flag
- Check your internet connection
- Consider using AWS Transfer Acceleration (additional cost)

### Issue: Disk Validation Failed - Unsupported File Format

**Error**: `disk validation failed [unsupported specified file format]`

**Cause**: AWS ImportSnapshot requires **uncompressed VMDK** files. The `.vmdk.gz` file was uploaded instead.

**Solution**:
```bash
# 1. Decompress the VMDK file
gunzip -k rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz

# 2. Upload uncompressed file to S3
aws s3 cp rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk \
  s3://${S3_BUCKET_NAME}/ \
  --region "$AWS_REGION"

# 3. Update containers.json to reference .vmdk (not .vmdk.gz)
# 4. Re-run import
```

The updated script now automatically decompresses the file before upload.

### Issue: Import Takes Very Long (>30 minutes)

**Solution**:
- This is normal for large VMDK files (~16GB uncompressed)
- Import typically takes 15-25 minutes
- Check status: `aws ec2 describe-import-snapshot-tasks`

### Issue: AMI Not Showing Up

**Solution**:
```bash
# Check AMI state
aws ec2 describe-images --region "$AWS_REGION" --image-ids "$CUSTOM_AMI"

# If Status is "pending", wait a few minutes
# If Status is "failed", check import snapshot logs
```

## Files in This Directory

| File | Type | Description |
|------|------|-------------|
| `create-kms-key.sh` | Script | Creates KMS key with bootstrap policy for OpenShift |
| `create-custom-ami.sh` | Script | Creates RHCOS AMI encrypted with your KMS key |
| `kms-bootstrap-policy.json` | Template | Initial KMS key policy (Terraform updates it later) |
| `README.md` | Documentation | This file |
| `kms-key-result.env` | Generated | KMS key details (after running create-kms-key.sh) |
| `custom-ami-result.env` | Generated | AMI details (after running create-custom-ami.sh) |
| `containers.json` | Generated | Import configuration (temporary, can delete) |
| `trust-policy.json` | Generated | vmimport trust policy (if created) |
| `role-policy.json` | Generated | vmimport role policy (if created) |

## Timeline

| Step | Duration | Notes |
|------|----------|-------|
| Download VMDK | 2-5 min | ~1GB compressed file |
| Decompress VMDK | 1-3 min | Expands to ~16GB |
| Upload to S3 | 10-15 min | ~16GB uncompressed file |
| Import Snapshot | 15-25 min | AWS processing time |
| Register AMI | <1 min | Nearly instant |
| **Total** | **30-50 min** | Mostly waiting for AWS |

## Next Steps

After creating the custom AMI:

1. **Update Terraform Variables**:
   ```hcl
   ami = "ami-your-custom-ami-id"
   ```

2. **Configure IMDSv2** in `install-config.yaml`:
   ```yaml
   metadataService:
     authentication: Required
   ```

3. **Continue with installer build** (Part 2 of main README)

## Cost

Approximate AWS costs:
- S3 storage: ~$0.023/GB/month (can delete after import)
- EBS snapshot: ~$0.05/GB/month (permanent)
- AMI: No additional cost (uses snapshot)

For 1 RHCOS snapshot (~16GB): **~$0.80/month**

## Security Notes

- ✅ Use customer-managed KMS keys for encryption
- ✅ Delete S3 bucket after AMI creation
- ✅ Restrict IAM permissions to minimum required
- ✅ Tag all resources for tracking
- ✅ Use KMS grants for time-limited access

## Version Compatibility

| Component | Version | Compatibility |
|-----------|---------|---------------|
| RHCOS | 4.16.51 | ✅ Latest as of Jan 2026 |
| OpenShift | 4.16.9+ | ✅ Compatible |
| AWS CLI | 2.x | ✅ Required |

## Differences from 4.14 Process

The process is **identical** to OpenShift 4.14, only the version numbers change:

| Aspect | OpenShift 4.14 | OpenShift 4.16 |
|--------|---------------|---------------|
| RHCOS Version | 4.14.x | 4.16.51 |
| VMDK URL | `.../4.14/...` | `.../4.16/...` |
| Process | VMDK Import | VMDK Import (same) |
| KMS Encryption | ✅ Supported | ✅ Supported |

If you have the PDF from your Red Hat consultant for 4.14, the steps are the same - just update version numbers.

## Additional Resources

- [Red Hat OpenShift 4.16 Installation Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/)
- [AWS Import/Export Documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/what-is-vmimport.html)
- [RHCOS Download Mirror](https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/)
- [AWS KMS Key Management](https://docs.aws.amazon.com/kms/latest/developerguide/)

## Support

For issues:
- **AMI Creation**: Red Hat OpenShift documentation (linked above)
- **AWS Import**: AWS Support or documentation
- **KMS Permissions**: AWS IAM/KMS documentation

---

**Document Version**: 2.0 (Updated to use Red Hat official VMDK process)  
**Last Updated**: January 21, 2026  
**Method**: Red Hat Official (VMDK Import with KMS)
