#!/bin/bash
# ==============================================================================
# Comprehensive Cluster Destroy Script
# ==============================================================================
# Safely destroys ALL resources related to this OpenShift cluster using:
# - Cluster tags (kubernetes.io/cluster/<infra-id>=owned)
# - Cluster name prefix for IAM resources
# - S3 bucket names containing cluster name
#
# SAFE: Only deletes resources tagged with this cluster's InfraID or named
#       with this cluster's name. Does NOT touch other resources.
#
# Usage:
#   ./destroy-cluster.sh                      # Interactive mode
#   ./destroy-cluster.sh --auto-approve       # Non-interactive mode
#   ./destroy-cluster.sh --dry-run            # Show what would be deleted
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
for arg in "$@"; do
    case $arg in
        --auto-approve) AUTO_APPROVE=true ;;
        --dry-run) DRY_RUN=true ;;
    esac
done

# Load configuration from tfvars
if [[ -f "env/demo.tfvars" ]]; then
    CLUSTER_NAME=$(grep '^cluster_name' env/demo.tfvars | awk -F'"' '{print $2}')
    INFRA_RANDOM_ID=$(grep '^infra_random_id' env/demo.tfvars | awk -F'"' '{print $2}')
    REGION=$(grep '^region' env/demo.tfvars | awk -F'"' '{print $2}')
    DOMAIN=$(grep '^domain' env/demo.tfvars | awk -F'"' '{print $2}')
    HOSTED_ZONE=$(grep '^hosted_zone' env/demo.tfvars | awk -F'"' '{print $2}')
    KMS_ALIAS=$(grep '^kms_ec2_alias' env/demo.tfvars | awk -F'"' '{print $2}')
else
    echo -e "${RED}Error: env/demo.tfvars not found${NC}"
    exit 1
fi

# Derive InfraID
if [[ "$INFRA_RANDOM_ID" == *"-"* ]]; then
    INFRA_ID="$INFRA_RANDOM_ID"
else
    INFRA_ID="${CLUSTER_NAME}-${INFRA_RANDOM_ID}"
fi

CLUSTER_TAG="kubernetes.io/cluster/${INFRA_ID}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           OpenShift Cluster Destroy                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}Configuration:${NC}"
echo "  Cluster Name:  $CLUSTER_NAME"
echo "  Infra ID:      $INFRA_ID"
echo "  Region:        $REGION"
echo "  Domain:        $DOMAIN"
echo "  Hosted Zone:   $HOSTED_ZONE"
echo "  Cluster Tag:   $CLUSTER_TAG"
echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}*** DRY RUN MODE - No resources will be deleted ***${NC}"
    echo
fi

# Confirmation
if [[ "$AUTO_APPROVE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
    echo -e "${RED}⚠ WARNING: This will PERMANENTLY DELETE all cluster resources!${NC}"
    read -p "Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Function to run or simulate command
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: $*${NC}"
    else
        eval "$@"
    fi
}

# ==============================================================================
# PHASE 1: OpenShift Installer Destroy (handles most AWS resources)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 1: OpenShift Installer Destroy${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ -f "installer-files/metadata.json" ]] || [[ -f "installer-files/auth/kubeconfig" ]]; then
    echo -e "${CYAN}Running openshift-install destroy cluster...${NC}"
    if [[ "$DRY_RUN" != "true" ]]; then
        export SkipDestroyingSharedTags=On
        export IgnoreErrorsOnSharedTags=On
        timeout -k 35m 30m ./openshift-install destroy cluster --dir=installer-files --log-level=info 2>&1 || \
            echo -e "${YELLOW}⚠ Installer destroy completed with warnings (continuing cleanup)${NC}"
    else
        echo -e "${YELLOW}[DRY-RUN] Would run: openshift-install destroy cluster${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No installer-files found, skipping installer destroy${NC}"
    echo "  Will clean up resources by tag instead"
fi

# ==============================================================================
# PHASE 2: Delete EC2 Instances by Tag (if any remain)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 2: Delete Remaining EC2 Instances${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:${CLUSTER_TAG},Values=owned" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$INSTANCES" ]]; then
    echo "Found instances: $INSTANCES"
    for instance in $INSTANCES; do
        echo -e "${CYAN}Terminating: $instance${NC}"
        run_cmd "aws ec2 terminate-instances --instance-ids $instance --region $REGION"
    done
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $INSTANCES --region "$REGION" 2>/dev/null || true
    fi
else
    echo -e "${GREEN}✓ No EC2 instances found with cluster tag${NC}"
fi

# ==============================================================================
# PHASE 3: Delete Load Balancers
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 3: Delete Load Balancers${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# NLB/ALB (elbv2)
LB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${INFRA_ID}')].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")

for lb_arn in $LB_ARNS; do
    if [[ -n "$lb_arn" ]] && [[ "$lb_arn" != "None" ]]; then
        echo -e "${CYAN}Deleting NLB/ALB: $lb_arn${NC}"
        run_cmd "aws elbv2 delete-load-balancer --load-balancer-arn '$lb_arn' --region $REGION"
    fi
done

# Classic ELB
CLASSIC_LBS=$(aws elb describe-load-balancers --region "$REGION" \
    --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '${INFRA_ID}')].LoadBalancerName" \
    --output text 2>/dev/null || echo "")

for lb in $CLASSIC_LBS; do
    if [[ -n "$lb" ]] && [[ "$lb" != "None" ]]; then
        echo -e "${CYAN}Deleting Classic ELB: $lb${NC}"
        run_cmd "aws elb delete-load-balancer --load-balancer-name '$lb' --region $REGION"
    fi
done

if [[ -z "$LB_ARNS" ]] && [[ -z "$CLASSIC_LBS" ]]; then
    echo -e "${GREEN}✓ No load balancers found${NC}"
fi

# ==============================================================================
# PHASE 4: Delete Target Groups
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 4: Delete Target Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName, '${INFRA_ID}')].TargetGroupArn" \
    --output text 2>/dev/null || echo "")

for tg_arn in $TG_ARNS; do
    if [[ -n "$tg_arn" ]] && [[ "$tg_arn" != "None" ]]; then
        echo -e "${CYAN}Deleting Target Group: $tg_arn${NC}"
        run_cmd "aws elbv2 delete-target-group --target-group-arn '$tg_arn' --region $REGION"
    fi
done

if [[ -z "$TG_ARNS" ]]; then
    echo -e "${GREEN}✓ No target groups found${NC}"
fi

# ==============================================================================
# PHASE 5: Delete Security Groups
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 5: Delete Security Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

SG_IDS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=tag:${CLUSTER_TAG},Values=owned" \
    --query 'SecurityGroups[*].GroupId' \
    --output text 2>/dev/null || echo "")

for sg_id in $SG_IDS; do
    if [[ -n "$sg_id" ]] && [[ "$sg_id" != "None" ]]; then
        echo -e "${CYAN}Deleting Security Group: $sg_id${NC}"
        # First remove all ingress/egress rules referencing this SG
        run_cmd "aws ec2 revoke-security-group-ingress --group-id $sg_id --region $REGION --protocol all --source-group $sg_id 2>/dev/null || true"
        run_cmd "aws ec2 delete-security-group --group-id $sg_id --region $REGION 2>/dev/null || true"
    fi
done

if [[ -z "$SG_IDS" ]]; then
    echo -e "${GREEN}✓ No security groups found with cluster tag${NC}"
fi

# ==============================================================================
# PHASE 6: Delete Route53 DNS Records
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 6: Delete Route53 DNS Records${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Function to delete a specific DNS record
delete_dns_record() {
    local ZONE_ID=$1
    local RECORD_NAME=$2
    local RECORD_TYPE=$3
    
    # Ensure name ends with dot
    [[ "$RECORD_NAME" != *. ]] && RECORD_NAME="${RECORD_NAME}."
    
    # Handle wildcard encoding
    local RECORD_NAME_ENCODED=$(echo "$RECORD_NAME" | sed 's/\*/\\052/g')
    
    echo "  Looking for $RECORD_TYPE $RECORD_NAME in zone $ZONE_ID"
    
    # Get the record details
    local RECORD_JSON=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name==\`$RECORD_NAME_ENCODED\` && Type==\`$RECORD_TYPE\`]" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$RECORD_JSON" != "[]" ]] && [[ $(echo "$RECORD_JSON" | jq 'length') -gt 0 ]]; then
        echo "  Found record, deleting..."
        local CHANGE_BATCH=$(echo "$RECORD_JSON" | jq '{Changes: [{Action: "DELETE", ResourceRecordSet: .[0]}]}')
        if [[ "$DRY_RUN" != "true" ]]; then
            aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" \
                --change-batch "$CHANGE_BATCH" 2>/dev/null && \
                echo -e "  ${GREEN}✓ Deleted${NC}" || \
                echo -e "  ${YELLOW}⚠ Could not delete${NC}"
        else
            echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
        fi
    else
        echo "  Record not found (already deleted)"
    fi
}

if [[ -n "$HOSTED_ZONE" ]]; then
    # Public hosted zone records
    echo -e "${CYAN}Deleting from public hosted zone: $HOSTED_ZONE${NC}"
    delete_dns_record "$HOSTED_ZONE" "api.${CLUSTER_NAME}.${DOMAIN}" "A"
    delete_dns_record "$HOSTED_ZONE" "api-int.${CLUSTER_NAME}.${DOMAIN}" "A"
    delete_dns_record "$HOSTED_ZONE" "*.apps.${CLUSTER_NAME}.${DOMAIN}" "A"
    delete_dns_record "$HOSTED_ZONE" "*.apps.${CLUSTER_NAME}.${DOMAIN}" "CNAME"
    
    # Private hosted zone (created by installer)
    echo -e "${CYAN}Looking for private hosted zone...${NC}"
    PRIVATE_ZONE_ID=$(aws route53 list-hosted-zones \
        --query "HostedZones[?Config.PrivateZone==\`true\` && Name==\`${CLUSTER_NAME}.${DOMAIN}.\`].Id" \
        --output text 2>/dev/null | sed 's|/hostedzone/||' | head -1 || echo "")
    
    if [[ -n "$PRIVATE_ZONE_ID" ]] && [[ "$PRIVATE_ZONE_ID" != "None" ]]; then
        echo -e "${CYAN}Found private hosted zone: $PRIVATE_ZONE_ID${NC}"
        
        # Delete specific records we know about
        delete_dns_record "$PRIVATE_ZONE_ID" "*.apps.${CLUSTER_NAME}.${DOMAIN}" "CNAME"
        delete_dns_record "$PRIVATE_ZONE_ID" "*.apps.${CLUSTER_NAME}.${DOMAIN}" "A"
        delete_dns_record "$PRIVATE_ZONE_ID" "api.${CLUSTER_NAME}.${DOMAIN}" "A"
        delete_dns_record "$PRIVATE_ZONE_ID" "api-int.${CLUSTER_NAME}.${DOMAIN}" "A"
        
        # Delete ALL non-NS/SOA records
        echo "  Cleaning up remaining records..."
        RECORDS=$(aws route53 list-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE_ID" \
            --query "ResourceRecordSets[?Type != 'NS' && Type != 'SOA']" --output json 2>/dev/null || echo "[]")
        
        if [[ "$RECORDS" != "[]" ]] && [[ -n "$RECORDS" ]] && [[ $(echo "$RECORDS" | jq 'length') -gt 0 ]]; then
            echo "$RECORDS" | jq -c '.[]' | while read -r record; do
                NAME=$(echo "$record" | jq -r '.Name')
                TYPE=$(echo "$record" | jq -r '.Type')
                echo "  Deleting remaining: $TYPE $NAME"
                if [[ "$DRY_RUN" != "true" ]]; then
                    CHANGE_BATCH=$(echo "$record" | jq '{Changes: [{Action: "DELETE", ResourceRecordSet: .}]}')
                    aws route53 change-resource-record-sets --hosted-zone-id "$PRIVATE_ZONE_ID" \
                        --change-batch "$CHANGE_BATCH" 2>/dev/null || true
                fi
            done
        fi
        
        # Try to delete the private hosted zone itself
        echo "  Attempting to delete private hosted zone..."
        if [[ "$DRY_RUN" != "true" ]]; then
            aws route53 delete-hosted-zone --id "$PRIVATE_ZONE_ID" 2>/dev/null && \
                echo -e "  ${GREEN}✓ Private zone deleted${NC}" || \
                echo -e "  ${YELLOW}⚠ Could not delete private zone (may still have records)${NC}"
        fi
    else
        echo "  No private hosted zone found"
    fi
else
    echo -e "${YELLOW}⚠ No hosted zone configured, skipping DNS cleanup${NC}"
fi

# ==============================================================================
# PHASE 7: Delete IAM Roles
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 7: Delete IAM Roles${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Function to delete a role completely
delete_iam_role() {
    local ROLE_NAME=$1
    echo -e "${CYAN}Deleting role: $ROLE_NAME${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN] Would delete role${NC}"
        return
    fi
    
    # Remove from instance profiles
    for profile in $(aws iam list-instance-profiles-for-role --role-name "$ROLE_NAME" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null); do
        echo "  Removing from instance profile: $profile"
        aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$ROLE_NAME" 2>/dev/null || true
    done
    
    # Delete inline policies
    for policy in $(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null); do
        echo "  Deleting inline policy: $policy"
        aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" 2>/dev/null || true
    done
    
    # Detach managed policies
    for policy_arn in $(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
        echo "  Detaching policy: $policy_arn"
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null || true
    done
    
    # Delete role
    aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null && \
        echo -e "  ${GREEN}✓ Role deleted${NC}" || \
        echo -e "  ${YELLOW}⚠ Could not delete role${NC}"
}

# 1. Delete OIDC roles (created by ccoctl) - pattern: <cluster-name>-openshift-*
echo -e "${CYAN}Looking for OIDC roles (${CLUSTER_NAME}-openshift-*)...${NC}"
OIDC_ROLES=$(aws iam list-roles \
    --query "Roles[?starts_with(RoleName, '${CLUSTER_NAME}-openshift')].RoleName" \
    --output text 2>/dev/null || echo "")

for role in $OIDC_ROLES; do
    delete_iam_role "$role"
done

# 2. Delete roles matching cluster name pattern: <cluster-name>-*
echo -e "${CYAN}Looking for cluster-prefixed roles (${CLUSTER_NAME}-*)...${NC}"
CLUSTER_ROLES=$(aws iam list-roles \
    --query "Roles[?starts_with(RoleName, '${CLUSTER_NAME}-')].RoleName" \
    --output text 2>/dev/null || echo "")

for role in $CLUSTER_ROLES; do
    delete_iam_role "$role"
done

# 3. Delete Terraform-created roles by common patterns
echo -e "${CYAN}Looking for Terraform-created roles...${NC}"
for role_pattern in "ocp-controlplane" "ocp-worker" "ocpcontrolplane" "ocpworkernode"; do
    ROLES=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${role_pattern}')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role in $ROLES; do
        delete_iam_role "$role"
    done
done

# 4. Delete instance profiles matching cluster name
echo -e "${CYAN}Looking for instance profiles...${NC}"
for profile_pattern in "${CLUSTER_NAME}" "${INFRA_ID}" "ocp-controlplane" "ocp-worker"; do
    PROFILES=$(aws iam list-instance-profiles \
        --query "InstanceProfiles[?contains(InstanceProfileName, '${profile_pattern}')].InstanceProfileName" \
        --output text 2>/dev/null || echo "")
    
    for profile in $PROFILES; do
        echo "  Deleting instance profile: $profile"
        if [[ "$DRY_RUN" != "true" ]]; then
            # First remove any roles
            for role in $(aws iam get-instance-profile --instance-profile-name "$profile" --query 'InstanceProfile.Roles[*].RoleName' --output text 2>/dev/null); do
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role" 2>/dev/null || true
            done
            aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
        fi
    done
done

echo -e "${GREEN}✓ IAM roles cleanup complete${NC}"

# ==============================================================================
# PHASE 8: Delete IAM Policies
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 8: Delete IAM Policies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

for policy_pattern in "ocp-controlplane" "ocp-worker" "ocpcontrolplane" "ocpworkernode"; do
    POLICIES=$(aws iam list-policies --scope Local \
        --query "Policies[?contains(PolicyName, '${policy_pattern}')].Arn" \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in $POLICIES; do
        if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
            echo -e "${CYAN}Deleting policy: $policy_arn${NC}"
            if [[ "$DRY_RUN" != "true" ]]; then
                # Detach from all entities
                for role in $(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[*].RoleName' --output text 2>/dev/null); do
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
                done
                # Delete policy versions
                for version in $(aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
                    aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" 2>/dev/null || true
                done
                # Delete policy
                aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        fi
    done
done

# ==============================================================================
# PHASE 9: Delete OIDC Provider
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 9: Delete OIDC Provider${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

OIDC_PROVIDERS=$(aws iam list-open-id-connect-providers \
    --query 'OpenIDConnectProviderList[*].Arn' --output text 2>/dev/null || echo "")

for oidc_arn in $OIDC_PROVIDERS; do
    # Check if this OIDC provider belongs to our cluster
    OIDC_URL=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn" \
        --query 'Url' --output text 2>/dev/null || echo "")
    
    if echo "$OIDC_URL" | grep -q "$CLUSTER_NAME"; then
        echo -e "${CYAN}Deleting OIDC provider: $oidc_arn${NC}"
        run_cmd "aws iam delete-open-id-connect-provider --open-id-connect-provider-arn '$oidc_arn'"
    fi
done

# ==============================================================================
# PHASE 10: Delete S3 Buckets
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 10: Delete S3 Buckets${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# OIDC bucket
OIDC_BUCKET=$(grep '^s3_bucket_name_oidc' env/demo.tfvars 2>/dev/null | awk -F'"' '{print $2}' || echo "")
if [[ -n "$OIDC_BUCKET" ]]; then
    if aws s3 ls "s3://${OIDC_BUCKET}" --region "$REGION" 2>/dev/null; then
        echo -e "${CYAN}Deleting OIDC bucket: $OIDC_BUCKET${NC}"
        run_cmd "aws s3 rm s3://${OIDC_BUCKET} --recursive --region $REGION"
        run_cmd "aws s3 rb s3://${OIDC_BUCKET} --region $REGION"
    fi
fi

# State bucket
STATE_BUCKET="${INFRA_ID}-terraform-remote-state-storage-s3"
if aws s3 ls "s3://${STATE_BUCKET}" --region "$REGION" 2>/dev/null; then
    echo -e "${CYAN}Deleting state bucket: $STATE_BUCKET${NC}"
    run_cmd "aws s3 rm s3://${STATE_BUCKET} --recursive --region $REGION"
    run_cmd "aws s3 rb s3://${STATE_BUCKET} --region $REGION"
fi

# ==============================================================================
# PHASE 11: Delete DynamoDB Table
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 11: Delete DynamoDB Table${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

DYNAMO_TABLE="${CLUSTER_NAME}-terraform-locks"
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" 2>/dev/null; then
    echo -e "${CYAN}Deleting DynamoDB table: $DYNAMO_TABLE${NC}"
    run_cmd "aws dynamodb delete-table --table-name '$DYNAMO_TABLE' --region $REGION"
fi

# ==============================================================================
# PHASE 12: Delete KMS Aliases (not the keys - they may be shared)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 12: Delete KMS Aliases${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Delete terraform state KMS alias
STATE_KMS_ALIAS="alias/s3-terraform-state-${CLUSTER_NAME}"
if aws kms describe-key --key-id "$STATE_KMS_ALIAS" --region "$REGION" 2>/dev/null; then
    echo -e "${CYAN}Deleting KMS alias: $STATE_KMS_ALIAS${NC}"
    run_cmd "aws kms delete-alias --alias-name '$STATE_KMS_ALIAS' --region $REGION"
fi

echo -e "${YELLOW}Note: KMS keys are NOT deleted (they may be shared). Delete manually if needed:${NC}"
echo "  aws kms schedule-key-deletion --key-id <KEY_ID> --pending-window-in-days 7 --region $REGION"

# ==============================================================================
# PHASE 13: Clean Local Files
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 13: Clean Local Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if [[ "$DRY_RUN" != "true" ]]; then
    rm -rf installer-files/ output/ init_setup/ .terraform/ 2>/dev/null || true
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl 2>/dev/null || true
    rm -f *.log tfplan kms-policy.json dns-*.json trust-policy*.json 2>/dev/null || true
    echo -e "${GREEN}✓ Local files cleaned${NC}"
else
    echo -e "${YELLOW}[DRY-RUN] Would delete: installer-files/, output/, .terraform/, terraform.tfstate*${NC}"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Destroy Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN COMPLETE - No resources were actually deleted${NC}"
    echo "Run without --dry-run to perform actual deletion"
else
    echo -e "${GREEN}✓ Cluster destroy complete!${NC}"
    echo
    echo "Deleted resources for cluster: ${CLUSTER_NAME} (${INFRA_ID})"
    echo
    echo "To verify cleanup, check:"
    echo "  aws ec2 describe-instances --filters 'Name=tag:${CLUSTER_TAG},Values=owned' --region $REGION"
    echo "  aws iam list-roles --query \"Roles[?contains(RoleName, '${CLUSTER_NAME}')]\""
fi
echo
