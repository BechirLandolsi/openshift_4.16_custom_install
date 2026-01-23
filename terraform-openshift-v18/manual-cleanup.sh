#!/bin/bash

# Manual cleanup script for OpenShift Terraform resources
# Use this when terraform destroy fails or resources are stuck

set -e

REGION="eu-west-3"
CLUSTER_NAME="my-ocp-cluster"
ACCOUNT_ID="051826696190"

echo "=========================================="
echo "Manual Cleanup Script"
echo "Region: $REGION"
echo "Cluster: $CLUSTER_NAME"
echo "=========================================="
echo ""

# Function to safely delete role
delete_role() {
    local ROLE_NAME=$1
    echo "Processing role: $ROLE_NAME"
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
        echo "  → Role exists, proceeding with cleanup..."
        
        # Detach all managed policies
        echo "  → Detaching managed policies..."
        aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text | while read -r POLICY_ARN; do
            if [ -n "$POLICY_ARN" ]; then
                echo "    → Detaching policy: $POLICY_ARN"
                aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
            fi
        done
        
        # Delete all inline policies
        echo "  → Deleting inline policies..."
        aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[*]' --output text | while read -r POLICY_NAME; do
            if [ -n "$POLICY_NAME" ]; then
                echo "    → Deleting inline policy: $POLICY_NAME"
                aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" 2>/dev/null || true
            fi
        done
        
        # Delete the role
        echo "  → Deleting role..."
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null && echo "  ✓ Role deleted" || echo "  ✗ Failed to delete role"
    else
        echo "  → Role does not exist (already deleted)"
    fi
    echo ""
}

# Function to safely delete policy
delete_policy() {
    local POLICY_NAME=$1
    local POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    echo "Processing policy: $POLICY_NAME"
    
    # Check if policy exists
    if aws iam get-policy --policy-arn "$POLICY_ARN" 2>/dev/null; then
        echo "  → Policy exists, proceeding with cleanup..."
        
        # Detach from all roles
        echo "  → Detaching policy from all roles..."
        aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --query 'PolicyRoles[*].RoleName' --output text | while read -r ROLE_NAME; do
            if [ -n "$ROLE_NAME" ]; then
                echo "    → Detaching from role: $ROLE_NAME"
                aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
            fi
        done
        
        # Delete all policy versions except default
        echo "  → Deleting non-default policy versions..."
        aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text | while read -r VERSION_ID; do
            if [ -n "$VERSION_ID" ]; then
                echo "    → Deleting version: $VERSION_ID"
                aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION_ID" 2>/dev/null || true
            fi
        done
        
        # Delete the policy
        echo "  → Deleting policy..."
        aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null && echo "  ✓ Policy deleted" || echo "  ✗ Failed to delete policy"
    else
        echo "  → Policy does not exist (already deleted)"
    fi
    echo ""
}

# Function to safely delete S3 bucket
delete_s3_bucket() {
    local BUCKET_NAME=$1
    
    echo "Processing S3 bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null; then
        echo "  → Bucket exists, proceeding with cleanup..."
        
        # Empty the bucket
        echo "  → Emptying bucket..."
        aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "$REGION" 2>/dev/null || true
        
        # Delete the bucket
        echo "  → Deleting bucket..."
        aws s3 rb "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null && echo "  ✓ Bucket deleted" || echo "  ✗ Failed to delete bucket"
    else
        echo "  → Bucket does not exist (already deleted)"
    fi
    echo ""
}

# Function to delete OIDC provider
delete_oidc_provider() {
    echo "Processing OIDC providers for cluster: $CLUSTER_NAME"
    
    # Find OIDC providers matching cluster name
    aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[*].Arn' --output text | while read -r OIDC_ARN; do
        if [ -n "$OIDC_ARN" ]; then
            # Get provider details
            OIDC_URL=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" --query 'Url' --output text 2>/dev/null || echo "")
            
            if echo "$OIDC_URL" | grep -q "$CLUSTER_NAME"; then
                echo "  → Found OIDC provider: $OIDC_ARN"
                echo "  → Deleting OIDC provider..."
                aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null && echo "  ✓ OIDC provider deleted" || echo "  ✗ Failed to delete OIDC provider"
            fi
        fi
    done
    echo ""
}

echo "=========================================="
echo "Step 1: Deleting IAM Roles"
echo "=========================================="
delete_role "ocp-controlplane-demo"
delete_role "ocp-worker-role"
delete_role "${CLUSTER_NAME}-openshift-ingress"
delete_role "${CLUSTER_NAME}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
delete_role "${CLUSTER_NAME}-openshift-machine-api-aws-cloud-credentials"
delete_role "${CLUSTER_NAME}-openshift-cloud-credential-operator-cloud-credential-operator-iam-ro"
delete_role "${CLUSTER_NAME}-openshift-image-registry-installer-cloud-credentials"

echo "=========================================="
echo "Step 2: Deleting IAM Policies"
echo "=========================================="
delete_policy "ocp-controlplane-policy-demo"
delete_policy "ocp-worker-policy-demo"

echo "=========================================="
echo "Step 3: Deleting S3 Buckets"
echo "=========================================="
delete_s3_bucket "ocp-euw3-oidc-demo"
delete_s3_bucket "${CLUSTER_NAME}-demo-d44a5-terraform-remote-state-storage-s3"

echo "=========================================="
echo "Step 4: Deleting OIDC Providers"
echo "=========================================="
delete_oidc_provider

echo "=========================================="
echo "Step 5: Cleanup Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Clean local directories: rm -rf output/ installer-files/"
echo "2. Run terraform apply again"
echo ""
