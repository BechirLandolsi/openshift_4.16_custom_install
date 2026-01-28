#!/bin/bash
# ==============================================================================
# Clean Cluster Script - Called by Terraform destroy
# ==============================================================================
# This script is called automatically by terraform destroy.
# It uses the comprehensive destroy-cluster.sh for thorough cleanup.
#
# Parameters (passed by Terraform):
#   $1 - hosted_zone
#   $2 - cluster_name
#   $3 - domain
#   $4 - bucket
# ==============================================================================

hostedzone=$1
cluster=$2
domain=$3
bucket=$4

echo "=============================================="
echo "OpenShift Cluster Cleanup"
echo "=============================================="
echo "Hosted Zone: $hostedzone"
echo "Cluster: $cluster"
echo "Domain: $domain"
echo "Bucket: $bucket"
echo ""

# Try to fetch installer files from S3 if not present locally
if [[ ! -f installer-files/auth/kubeconfig ]]; then
    echo "Kubeconfig not found locally. Attempting to fetch from S3..."
    if aws s3 cp s3://$bucket/installer-files.tar installer-files.tar 2>/dev/null; then
        echo "✓ Files fetched from S3"
        tar xvf installer-files.tar
    else
        echo "⚠ Warning: Could not fetch from S3 (bucket may not exist)"
        echo "Continuing with cleanup using cluster tags..."
    fi
fi

# Use comprehensive destroy script if available
if [[ -f "destroy-cluster.sh" ]]; then
    echo ""
    echo "Using comprehensive destroy-cluster.sh..."
    chmod +x destroy-cluster.sh
    ./destroy-cluster.sh --auto-approve
else
    # Fallback to basic cleanup
    echo ""
    echo "Fallback: Running basic cleanup..."
    
    # Run OpenShift installer destroy
    echo "Running openshift-install destroy..."
    export SkipDestroyingSharedTags=On
    export IgnoreErrorsOnSharedTags=On
    timeout -k 30m 25m sh delete-cluster.sh || echo "⚠ Installer destroy had warnings"
    
    # Delete DNS records
    echo "Deleting DNS records..."
    sh delete-record.sh $hostedzone api.$cluster.$domain 2>/dev/null || true
    sh delete-record.sh $hostedzone api-int.$cluster.$domain 2>/dev/null || true
    sh delete-record.sh $hostedzone "*.apps.$cluster.$domain" 2>/dev/null || true
    
    # Delete IAM roles
    echo "Deleting IAM roles..."
    sh delete-roles.sh $cluster 2>/dev/null || true
fi

echo ""
echo "=============================================="
echo "Cleanup complete"
echo "=============================================="
