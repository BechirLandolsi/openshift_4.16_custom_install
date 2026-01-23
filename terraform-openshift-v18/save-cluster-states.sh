#!/bin/bash
# Save cluster state files
# If S3 bucket is provided, backup to S3. Otherwise, just keep locally.

bucket=$1

# Create local backup
echo "Creating local backup..."
tar cvf installer-files.tar installer-files
echo "✓ Local backup created: installer-files.tar"

# Upload to S3 if bucket exists
if [ -n "$bucket" ]; then
    echo "Checking if S3 bucket exists..."
    if aws s3 ls s3://$bucket 2>/dev/null; then
        echo "Uploading to S3..."
        aws s3 cp installer-files.tar s3://$bucket/installer-files.tar
        echo "✓ Backup uploaded to S3: s3://$bucket/installer-files.tar"
    else
        echo "⚠ Warning: S3 bucket $bucket does not exist. Skipping S3 upload."
        echo "✓ Files saved locally in installer-files/ directory"
    fi
else
    echo "✓ No S3 bucket specified. Files saved locally."
fi

exit 0

