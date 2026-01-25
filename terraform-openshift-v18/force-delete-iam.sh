#!/bin/bash

# Force delete IAM roles and policies that are blocking Terraform
# This script handles all attached policies and inline policies

set +e  # Don't exit on errors

echo "=========================================="
echo "Force Delete IAM Resources"
echo "=========================================="
echo ""

# Function to delete a role completely
delete_role_completely() {
    local ROLE_NAME=$1
    echo "Processing role: $ROLE_NAME"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo "  → Role does not exist, skipping"
        echo ""
        return 0
    fi
    
    echo "  → Role exists, cleaning up..."
    
    # 1. Detach all managed policies
    echo "  → Detaching managed policies..."
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
    if [ -n "$POLICIES" ]; then
        for POLICY_ARN in $POLICIES; do
            echo "    → Detaching: $POLICY_ARN"
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null
        done
    else
        echo "    → No managed policies attached"
    fi
    
    # 2. Delete all inline policies
    echo "  → Deleting inline policies..."
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[*]' --output text 2>/dev/null)
    if [ -n "$INLINE_POLICIES" ]; then
        for POLICY_NAME in $INLINE_POLICIES; do
            echo "    → Deleting inline: $POLICY_NAME"
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" 2>/dev/null
        done
    else
        echo "    → No inline policies found"
    fi
    
    # 3. Remove from instance profiles
    echo "  → Removing from instance profiles..."
    INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$ROLE_NAME" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null)
    if [ -n "$INSTANCE_PROFILES" ]; then
        for PROFILE in $INSTANCE_PROFILES; do
            echo "    → Removing from profile: $PROFILE"
            aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE_NAME" 2>/dev/null
        done
    else
        echo "    → Not in any instance profiles"
    fi
    
    # 4. Delete the role
    echo "  → Deleting role..."
    if aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null; then
        echo "  ✓ Role deleted successfully"
    else
        echo "  ✗ Failed to delete role"
    fi
    echo ""
}

# Function to delete a policy completely
delete_policy_completely() {
    local POLICY_NAME=$1
    local POLICY_ARN="arn:aws:iam::051826696190:policy/${POLICY_NAME}"
    
    echo "Processing policy: $POLICY_NAME"
    
    # Check if policy exists
    if ! aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        echo "  → Policy does not exist, skipping"
        echo ""
        return 0
    fi
    
    echo "  → Policy exists, cleaning up..."
    
    # 1. Detach from all roles
    echo "  → Detaching from all roles..."
    ATTACHED_ROLES=$(aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --query 'PolicyRoles[*].RoleName' --output text 2>/dev/null)
    if [ -n "$ATTACHED_ROLES" ]; then
        for ROLE in $ATTACHED_ROLES; do
            echo "    → Detaching from role: $ROLE"
            aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null
        done
    else
        echo "    → Not attached to any roles"
    fi
    
    # 2. Detach from all users
    echo "  → Detaching from all users..."
    ATTACHED_USERS=$(aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --query 'PolicyUsers[*].UserName' --output text 2>/dev/null)
    if [ -n "$ATTACHED_USERS" ]; then
        for USER in $ATTACHED_USERS; do
            echo "    → Detaching from user: $USER"
            aws iam detach-user-policy --user-name "$USER" --policy-arn "$POLICY_ARN" 2>/dev/null
        done
    else
        echo "    → Not attached to any users"
    fi
    
    # 3. Detach from all groups
    echo "  → Detaching from all groups..."
    ATTACHED_GROUPS=$(aws iam list-entities-for-policy --policy-arn "$POLICY_ARN" --query 'PolicyGroups[*].GroupName' --output text 2>/dev/null)
    if [ -n "$ATTACHED_GROUPS" ]; then
        for GROUP in $ATTACHED_GROUPS; do
            echo "    → Detaching from group: $GROUP"
            aws iam detach-group-policy --group-name "$GROUP" --policy-arn "$POLICY_ARN" 2>/dev/null
        done
    else
        echo "    → Not attached to any groups"
    fi
    
    # 4. Delete all non-default policy versions
    echo "  → Deleting non-default policy versions..."
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null)
    if [ -n "$VERSIONS" ]; then
        for VERSION in $VERSIONS; do
            echo "    → Deleting version: $VERSION"
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" 2>/dev/null
        done
    else
        echo "    → No non-default versions found"
    fi
    
    # 5. Delete the policy
    echo "  → Deleting policy..."
    if aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null; then
        echo "  ✓ Policy deleted successfully"
    else
        echo "  ✗ Failed to delete policy"
    fi
    echo ""
}

echo "=========================================="
echo "Step 1: Deleting IAM Roles"
echo "=========================================="

# Delete all known roles
delete_role_completely "ocp-controlplane-demo"
delete_role_completely "ocp-worker-role"

echo "=========================================="
echo "Step 2: Deleting IAM Policies"
echo "=========================================="

# Delete all known policies
delete_policy_completely "ocp-controlplane-policy-demo"
delete_policy_completely "ocp-worker-policy-demo"

echo "=========================================="
echo "Step 3: Deleting S3 Buckets"
echo "=========================================="

# Delete OIDC bucket
BUCKET_NAME="ocp-euw3-oidc-demo"
echo "Processing S3 bucket: $BUCKET_NAME"
if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    echo "  → Bucket exists, emptying and deleting..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null
    aws s3 rb "s3://${BUCKET_NAME}" 2>/dev/null && echo "  ✓ Bucket deleted" || echo "  ✗ Failed to delete bucket"
else
    echo "  → Bucket does not exist"
fi
echo ""

echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Clean local directories: rm -rf output/ installer-files/ .terraform/ terraform.tfstate*"
echo "2. Re-initialize: terraform init"
echo "3. Run terraform apply"
echo ""
