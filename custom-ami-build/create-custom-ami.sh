#!/bin/bash
# Script to create custom RHCOS AMI with KMS encryption for OpenShift 4.16
# Based on Red Hat official documentation:
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-upload-custom-rhcos-ami_installing-aws-secret-region

set -euo pipefail

# Configuration variables - UPDATE THESE
RHCOS_VERSION="${RHCOS_VERSION:-4.16.51}"
REGION="${AWS_REGION:-eu-west-1}"
KMS_KEY_ID="${KMS_KEY_ID:-}"  # ARN or alias of your KMS key
S3_BUCKET_NAME="${S3_BUCKET_NAME:-rhcos-import-${REGION}-$(date +%s)}"

# Validate required variables
if [ -z "$KMS_KEY_ID" ]; then
    echo "ERROR: KMS_KEY_ID environment variable must be set"
    echo "Example: export KMS_KEY_ID='arn:aws:kms:eu-west-1:123456789012:key/...'"
    echo "     or: export KMS_KEY_ID='alias/my-kms-key'"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}RHCOS Custom AMI Creation Script${NC}"
echo -e "${GREEN}OpenShift 4.16 with KMS Encryption${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Configuration:"
echo "  RHCOS Version: $RHCOS_VERSION"
echo "  AWS Region: $REGION"
echo "  KMS Key: $KMS_KEY_ID"
echo "  S3 Bucket: $S3_BUCKET_NAME"
echo ""

# Step 1: Download RHCOS VMDK
echo -e "${YELLOW}Step 1: Downloading RHCOS VMDK...${NC}"
VMDK_GZ_FILE="rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz"
VMDK_FILE="rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk"
VMDK_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/${RHCOS_VERSION}/${VMDK_GZ_FILE}"

if [ ! -f "$VMDK_FILE" ]; then
    if [ ! -f "$VMDK_GZ_FILE" ]; then
        echo "Downloading $VMDK_GZ_FILE..."
        wget "$VMDK_URL"
        echo -e "${GREEN}✓ Download complete${NC}"
    else
        echo -e "${GREEN}✓ Compressed VMDK file already exists${NC}"
    fi
    
    # Decompress the file (AWS ImportSnapshot requires uncompressed VMDK)
    echo "Decompressing $VMDK_GZ_FILE..."
    gunzip -k "$VMDK_GZ_FILE"
    echo -e "${GREEN}✓ Decompression complete${NC}"
else
    echo -e "${GREEN}✓ Uncompressed VMDK file already exists${NC}"
fi

# Step 2: Create S3 bucket
echo -e "${YELLOW}Step 2: Creating S3 bucket...${NC}"
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ Bucket already exists${NC}"
else
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION"
    else
        aws s3api create-bucket \
          --bucket "$S3_BUCKET_NAME" \
          --region "$REGION" \
          --create-bucket-configuration LocationConstraint="$REGION"
    fi
    echo -e "${GREEN}✓ S3 bucket created${NC}"
fi

# Step 3: Upload VMDK to S3
echo -e "${YELLOW}Step 3: Uploading uncompressed VMDK to S3 (may take 10-15 minutes)...${NC}"
echo "Note: Uploading uncompressed file (~16GB). This will take some time."
aws s3 cp "$VMDK_FILE" "s3://${S3_BUCKET_NAME}/" --region "$REGION"
echo -e "${GREEN}✓ Upload complete${NC}"

# Step 4: Create containers.json for import
echo -e "${YELLOW}Step 4: Creating import configuration...${NC}"
cat > containers.json <<EOF
{
  "Description": "rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64",
  "Format": "vmdk",
  "UserBucket": {
    "S3Bucket": "${S3_BUCKET_NAME}",
    "S3Key": "$(basename ${VMDK_FILE})"
  }
}
EOF
echo -e "${GREEN}✓ Configuration created${NC}"

# Step 5: Import snapshot with KMS encryption
echo -e "${YELLOW}Step 5: Importing snapshot with KMS encryption...${NC}"
IMPORT_TASK_ID=$(aws ec2 import-snapshot \
  --region "$REGION" \
  --description "RHCOS ${RHCOS_VERSION} for OpenShift 4.16" \
  --disk-container "file://containers.json" \
  --encrypted \
  --kms-key-id "$KMS_KEY_ID" \
  --query 'ImportTaskId' \
  --output text)

echo "Import Task ID: $IMPORT_TASK_ID"
echo -e "${YELLOW}Waiting for import to complete (10-20 minutes)...${NC}"

# Poll for completion
while true; do
    STATUS=$(aws ec2 describe-import-snapshot-tasks \
      --region "$REGION" \
      --import-task-ids "$IMPORT_TASK_ID" \
      --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' \
      --output text)
    
    PROGRESS=$(aws ec2 describe-import-snapshot-tasks \
      --region "$REGION" \
      --import-task-ids "$IMPORT_TASK_ID" \
      --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Progress' \
      --output text 2>/dev/null || echo "0")
    
    echo -ne "\rStatus: $STATUS - Progress: ${PROGRESS}%     "
    
    if [ "$STATUS" = "completed" ]; then
        echo ""
        echo -e "${GREEN}✓ Import completed${NC}"
        break
    elif [ "$STATUS" = "deleted" ] || [ "$STATUS" = "deleting" ]; then
        echo -e "${RED}✗ Import failed or was deleted${NC}"
        exit 1
    fi
    
    sleep 30
done

# Get snapshot ID
SNAPSHOT_ID=$(aws ec2 describe-import-snapshot-tasks \
  --region "$REGION" \
  --import-task-ids "$IMPORT_TASK_ID" \
  --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' \
  --output text)

echo "Snapshot ID: $SNAPSHOT_ID"

# Step 6: Verify encryption
echo -e "${YELLOW}Step 6: Verifying KMS encryption...${NC}"
aws ec2 describe-snapshots \
  --region "$REGION" \
  --snapshot-ids "$SNAPSHOT_ID" \
  --query 'Snapshots[0].[Encrypted,KmsKeyId]' \
  --output table

# Step 7: Register AMI
echo -e "${YELLOW}Step 7: Registering custom AMI...${NC}"
CUSTOM_AMI=$(aws ec2 register-image \
  --region "$REGION" \
  --name "rhcos-${RHCOS_VERSION}-x86_64-ocp416-kms" \
  --description "RHCOS ${RHCOS_VERSION} for OpenShift 4.16 with KMS encryption" \
  --architecture x86_64 \
  --virtualization-type hvm \
  --root-device-name '/dev/xvda' \
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={DeleteOnTermination=true,SnapshotId=${SNAPSHOT_ID},VolumeType=gp3,VolumeSize=120}" \
  --ena-support \
  --query 'ImageId' \
  --output text)

echo -e "${GREEN}✓ AMI registered: $CUSTOM_AMI${NC}"

# Step 8: Tag AMI
echo -e "${YELLOW}Step 8: Tagging AMI...${NC}"
aws ec2 create-tags \
  --region "$REGION" \
  --resources "$CUSTOM_AMI" "$SNAPSHOT_ID" \
  --tags \
    Key=Name,Value="RHCOS ${RHCOS_VERSION} OpenShift 4.16 Custom" \
    Key=OS,Value=RHCOS \
    Key=OS-Version,Value="${RHCOS_VERSION}" \
    Key=OCP-Version,Value=4.16 \
    Key=Encrypted,Value=KMS \
    Key=Compliance,Value=Required

echo -e "${GREEN}✓ Tags applied${NC}"

# Step 9: Save results
echo -e "${YELLOW}Step 9: Saving results...${NC}"
cat > custom-ami-result.env <<EOF
# Custom RHCOS AMI for OpenShift 4.16
# Created: $(date)
export CUSTOM_AMI="${CUSTOM_AMI}"
export REGION="${REGION}"
export RHCOS_VERSION="${RHCOS_VERSION}"
export SNAPSHOT_ID="${SNAPSHOT_ID}"
export KMS_KEY_ID="${KMS_KEY_ID}"
EOF

echo -e "${GREEN}✓ Results saved to custom-ami-result.env${NC}"

# Step 10: Optional cleanup
echo ""
echo -e "${YELLOW}Optional: Cleanup${NC}"
echo "To delete the S3 bucket and VMDK files, run:"
echo "  aws s3 rm s3://${S3_BUCKET_NAME}/$(basename ${VMDK_FILE})"
echo "  aws s3api delete-bucket --bucket ${S3_BUCKET_NAME} --region ${REGION}"
echo ""
echo "To delete local files (saves ~16GB):"
echo "  rm ${VMDK_FILE}"
echo "  # Keep compressed file: ${VMDK_GZ_FILE}"

# Summary
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Custom AMI Creation Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "AMI ID: $CUSTOM_AMI"
echo "Region: $REGION"
echo "RHCOS Version: $RHCOS_VERSION"
echo ""
echo "Next steps:"
echo "1. Source the environment file: source custom-ami-result.env"
echo "2. Use AMI ID in terraform tfvars:"
echo "   ami = \"$CUSTOM_AMI\""
echo "   aws_worker_iam_id = \"$CUSTOM_AMI\""
echo ""
echo "3. Configure IMDSv2 in install-config.yaml:"
echo "   metadataService:"
echo "     authentication: Required"
echo ""
