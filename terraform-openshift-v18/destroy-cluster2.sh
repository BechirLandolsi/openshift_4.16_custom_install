#!/bin/bash
# ==============================================================================
# Targeted Cluster Destroy Script
# ==============================================================================
# Deletes ONLY the specific resources created by this OpenShift installation:
# - DNS Records (api, api-int)
# - OIDC IAM Roles (6 roles)
# - Terraform IAM Roles (2 roles)
# - Terraform IAM Policies (2 policies)
#
# Usage:
#   ./destroy-cluster.sh                          # Interactive mode
#   ./destroy-cluster.sh --auto-approve           # Non-interactive mode
#   ./destroy-cluster.sh --dry-run                # Show what would be deleted
#   ./destroy-cluster.sh --var-file=env/prod.tfvars  # Specify tfvars file
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
AUTO_APPROVE=false
DRY_RUN=false
TFVARS_FILE=""

for arg in "$@"; do
    case $arg in
        --auto-approve) AUTO_APPROVE=true ;;
        --dry-run) DRY_RUN=true ;;
        --var-file=*) TFVARS_FILE="${arg#*=}" ;;
        *.tfvars) TFVARS_FILE="$arg" ;;
    esac
done

# Find tfvars file
if [[ -z "$TFVARS_FILE" ]]; then
    TFVARS_FILE="${TF_VAR_FILE:-}"
fi
if [[ -z "$TFVARS_FILE" ]]; then
    for f in "env/demo.tfvars" "env/prod.tfvars" "env/staging.tfvars" "terraform.tfvars"; do
        if [[ -f "$f" ]]; then
            TFVARS_FILE="$f"
            break
        fi
    done
fi

# Load configuration from tfvars
if [[ -n "$TFVARS_FILE" ]] && [[ -f "$TFVARS_FILE" ]]; then
    echo -e "${CYAN}Loading configuration from: ${TFVARS_FILE}${NC}"
    CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    DOMAIN=$(grep '^domain' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    HOSTED_ZONE=$(grep '^hosted_zone' "$TFVARS_FILE" | awk -F'"' '{print $2}')
else
    echo -e "${RED}Error: No tfvars file found${NC}"
    echo "Usage: $0 [--var-file=env/myfile.tfvars] [--dry-run] [--auto-approve]"
    exit 1
fi

# Validate required variables
if [[ -z "$CLUSTER_NAME" ]]; then
    echo -e "${RED}Error: cluster_name not found in tfvars${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           OpenShift Cluster Destroy (Targeted)                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}Configuration:${NC}"
echo "  Cluster Name:  $CLUSTER_NAME"
echo "  Region:        $REGION"
echo "  Domain:        $DOMAIN"
echo "  Hosted Zone:   $HOSTED_ZONE"
echo

# Define exact resources to delete
DNS_RECORDS=(
    "api.${CLUSTER_NAME}.${DOMAIN}"
    "api-int.${CLUSTER_NAME}.${DOMAIN}"
)

IAM_ROLES=(
    "${CLUSTER_NAME}-openshift-cloud-credential-operator-cloud-credential-operat"
    "${CLUSTER_NAME}-openshift-cloud-network-config-controller-cloud-credentials"
    "${CLUSTER_NAME}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
    "${CLUSTER_NAME}-openshift-image-registry-installer-cloud-credentials"
    "${CLUSTER_NAME}-openshift-ingress-operator-cloud-credentials"
    "${CLUSTER_NAME}-openshift-machine-api-aws-cloud-credentials"
    "ocpcontrolplane-${CLUSTER_NAME}-iam-role"
    "ocpworkernode-${CLUSTER_NAME}-iam-role"
)

IAM_POLICIES=(
    "ocpworkernode-policy-${CLUSTER_NAME}-iam-policy"
    "ocpcontrolplane-policy-${CLUSTER_NAME}-iam-policy"
)

echo -e "${CYAN}Resources to delete:${NC}"
echo
echo "  DNS Records:"
for record in "${DNS_RECORDS[@]}"; do
    echo "    - $record"
done
echo
echo "  IAM Roles:"
for role in "${IAM_ROLES[@]}"; do
    echo "    - $role"
done
echo
echo "  IAM Policies:"
for policy in "${IAM_POLICIES[@]}"; do
    echo "    - $policy"
done
echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  DRY RUN MODE - No resources will be deleted                   ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
fi

# Confirmation
if [[ "$AUTO_APPROVE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
    echo -e "${RED}⚠ WARNING: This will PERMANENTLY DELETE the resources listed above!${NC}"
    read -p "Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Helper function
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN] Would run: $1${NC}"
    else
        eval "$1"
    fi
}

# ==============================================================================
# PHASE 1: Run OpenShift Installer Destroy
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 1: OpenShift Installer Destroy${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

echo -e "${CYAN}Running openshift-install destroy cluster...${NC}"
echo -e "${CYAN}Environment: SkipDestroyingSharedTags=On IgnoreErrorsOnSharedTags=On${NC}"

if [[ "$DRY_RUN" != "true" ]]; then
    # Run openshift-install destroy with environment variables to protect shared resources
    # - SkipDestroyingSharedTags=On: Don't destroy resources with shared tags (subnets, VPC, etc.)
    # - IgnoreErrorsOnSharedTags=On: Continue even if shared tag operations fail
    SkipDestroyingSharedTags=On IgnoreErrorsOnSharedTags=On \
        ./openshift-install destroy cluster --dir=installer-files --log-level=debug 2>&1 || \
        echo -e "${YELLOW}⚠ Installer destroy completed with warnings (this is normal for shared VPC)${NC}"
else
    echo -e "  ${YELLOW}[DRY-RUN] Would run:${NC}"
    echo -e "  ${YELLOW}SkipDestroyingSharedTags=On IgnoreErrorsOnSharedTags=On ./openshift-install destroy cluster --dir=installer-files --log-level=debug${NC}"
fi

echo -e "${GREEN}✓ OpenShift installer destroy phase complete${NC}"

# ==============================================================================
# PHASE 2: Delete DNS Records
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 2: Delete DNS Records${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

delete_dns_record() {
    local zone_id="$1"
    local record_name="$2"
    
    # Ensure record name ends with a dot
    [[ "$record_name" != *. ]] && record_name="${record_name}."
    
    echo -e "${CYAN}Looking for: $record_name${NC}"
    
    # Get the record
    RECORD_JSON=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --query "ResourceRecordSets[?Name=='${record_name}']" \
        --output json 2>/dev/null)
    
    if [[ "$RECORD_JSON" == "[]" ]] || [[ -z "$RECORD_JSON" ]]; then
        echo -e "  ${GREEN}✓ Record not found (already deleted)${NC}"
        return 0
    fi
    
    # Process each matching record
    echo "$RECORD_JSON" | jq -c '.[]' | while read -r record; do
        local rtype=$(echo "$record" | jq -r '.Type')
        
        # Skip NS and SOA records
        if [[ "$rtype" == "NS" ]] || [[ "$rtype" == "SOA" ]]; then
            echo -e "  ${YELLOW}⚠ Skipping $rtype record${NC}"
            continue
        fi
        
        echo -e "  Deleting $rtype record..."
        
        if [[ "$DRY_RUN" != "true" ]]; then
            CHANGE_BATCH=$(jq -n --argjson record "$record" '{
                "Changes": [{
                    "Action": "DELETE",
                    "ResourceRecordSet": $record
                }]
            }')
            
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$zone_id" \
                --change-batch "$CHANGE_BATCH" 2>/dev/null && \
                echo -e "  ${GREEN}✓ Deleted${NC}" || \
                echo -e "  ${YELLOW}⚠ Could not delete${NC}"
        else
            echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
        fi
    done
}

for record in "${DNS_RECORDS[@]}"; do
    delete_dns_record "$HOSTED_ZONE" "$record"
done

# ==============================================================================
# PHASE 3: Delete IAM Roles
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 3: Delete IAM Roles${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

delete_iam_role() {
    local role_name="$1"
    
    echo -e "${CYAN}Checking: $role_name${NC}"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" 2>/dev/null >/dev/null; then
        echo -e "  ${GREEN}✓ Role not found (already deleted)${NC}"
        return 0
    fi
    
    echo -e "  Deleting role..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Detach managed policies
        for policy_arn in $(aws iam list-attached-role-policies --role-name "$role_name" \
            --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies
        for policy_name in $(aws iam list-role-policies --role-name "$role_name" \
            --query 'PolicyNames[*]' --output text 2>/dev/null); do
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Remove from instance profiles
        for profile in $(aws iam list-instance-profiles-for-role --role-name "$role_name" \
            --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null); do
            aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role_name" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$role_name" 2>/dev/null && \
            echo -e "  ${GREEN}✓ Deleted${NC}" || \
            echo -e "  ${YELLOW}⚠ Could not delete${NC}"
    else
        echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
    fi
}

for role in "${IAM_ROLES[@]}"; do
    delete_iam_role "$role"
done

# ==============================================================================
# PHASE 4: Delete IAM Policies
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 4: Delete IAM Policies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

delete_iam_policy() {
    local policy_name="$1"
    local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
    
    echo -e "${CYAN}Checking: $policy_name${NC}"
    
    # Check if policy exists
    if ! aws iam get-policy --policy-arn "$policy_arn" 2>/dev/null >/dev/null; then
        echo -e "  ${GREEN}✓ Policy not found (already deleted)${NC}"
        return 0
    fi
    
    echo -e "  Deleting policy..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Detach from all roles
        for role in $(aws iam list-entities-for-policy --policy-arn "$policy_arn" \
            --query 'PolicyRoles[*].RoleName' --output text 2>/dev/null); do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete non-default versions
        for version in $(aws iam list-policy-versions --policy-arn "$policy_arn" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
            aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" 2>/dev/null || true
        done
        
        # Delete the policy
        aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null && \
            echo -e "  ${GREEN}✓ Deleted${NC}" || \
            echo -e "  ${YELLOW}⚠ Could not delete${NC}"
    else
        echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
    fi
}

for policy in "${IAM_POLICIES[@]}"; do
    delete_iam_policy "$policy"
done

# ==============================================================================
# NOTE: Local files are NOT deleted (installer-files/, output/, tfstate, etc.)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Local Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Local files preserved (installer-files/, output/, terraform.tfstate)${NC}"
echo -e "${YELLOW}  To delete manually if needed: rm -rf installer-files/ output/${NC}"

# ==============================================================================
# Summary
# ==============================================================================
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}║           DRY RUN COMPLETE                                     ║${NC}"
else
    echo -e "${BLUE}║           DESTROY COMPLETE                                     ║${NC}"
fi
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Cluster: ${CLUSTER_NAME}${NC}"
echo
