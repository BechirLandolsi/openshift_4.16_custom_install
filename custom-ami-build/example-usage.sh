#!/bin/bash
# Example: How to use create-custom-ami.sh
# This is a reference script showing the complete process

# Step 1: Set your environment variables
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"
# Or use alias: export KMS_KEY_ID="alias/plaasma-ec2-cmk"

# Optional: Customize S3 bucket name
# export S3_BUCKET_NAME="my-custom-bucket-name"

# Step 2: Run the automated script
./create-custom-ami.sh

# Step 3: Source the results
source custom-ami-result.env

# Step 4: Verify the AMI
echo "Custom AMI ID: $CUSTOM_AMI"
echo "Region: $AWS_REGION"
echo "RHCOS Version: $RHCOS_VERSION"
echo "Snapshot ID: $SNAPSHOT_ID"

# Step 5: Verify encryption
aws ec2 describe-snapshots \
  --region "$AWS_REGION" \
  --snapshot-ids "$SNAPSHOT_ID" \
  --query 'Snapshots[0].[Encrypted,KmsKeyId]' \
  --output table

# Step 6: Use in Terraform
cat > ../terraform-update.txt <<TFVARS
# Add to your terraform-openshift-v18/env/your-cluster.tfvars:
ami               = "$CUSTOM_AMI"
aws_worker_iam_id = "$CUSTOM_AMI"
TFVARS

echo "AMI creation complete! See terraform-update.txt for tfvars values."
