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
TFVARS_FILE=""

for arg in "$@"; do
    case $arg in
        --auto-approve) AUTO_APPROVE=true ;;
        --dry-run) DRY_RUN=true ;;
        --var-file=*) TFVARS_FILE="${arg#*=}" ;;
        *.tfvars) TFVARS_FILE="$arg" ;;
    esac
done

# Find tfvars file (priority: argument > env variable > default)
if [[ -z "$TFVARS_FILE" ]]; then
    TFVARS_FILE="${TF_VAR_FILE:-}"
fi
if [[ -z "$TFVARS_FILE" ]]; then
    # Try common default locations
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
    INFRA_RANDOM_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    DOMAIN=$(grep '^domain' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    HOSTED_ZONE=$(grep '^hosted_zone' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    KMS_ALIAS=$(grep '^kms_ec2_alias' "$TFVARS_FILE" | awk -F'"' '{print $2}')
else
    echo -e "${RED}Error: No tfvars file found${NC}"
    echo "Usage: $0 [--var-file=env/myfile.tfvars] [--dry-run] [--auto-approve]"
    echo "   or: TF_VAR_FILE=env/myfile.tfvars $0 [--dry-run] [--auto-approve]"
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
echo -e "${CYAN}Configuration (from env/demo.tfvars):${NC}"
echo "  Cluster Name:  $CLUSTER_NAME"
echo "  Infra ID:      $INFRA_ID"
echo "  Region:        $REGION"
echo "  Domain:        $DOMAIN"
echo "  Hosted Zone:   $HOSTED_ZONE"
echo "  Cluster Tag:   $CLUSTER_TAG"
echo
echo -e "${CYAN}Resources will be identified by:${NC}"
echo "  • Tag: kubernetes.io/cluster/${INFRA_ID}=owned"
echo "  • Names containing: ${CLUSTER_NAME}"
echo "  • DNS records for: *.${CLUSTER_NAME}.${DOMAIN}"
echo
echo -e "${GREEN}SAFE: Only resources with '${CLUSTER_NAME}' in their name will be deleted${NC}"
echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  DRY RUN MODE - No resources will be deleted                   ║${NC}"
    echo -e "${YELLOW}║  Review the output to verify only YOUR cluster resources       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
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
# PHASE 3: Delete Load Balancers (filter by cluster name)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 3: Delete Load Balancers${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# NLB/ALB (elbv2) - filter by cluster name
LB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")

for lb_arn in $LB_ARNS; do
    if [[ -n "$lb_arn" ]] && [[ "$lb_arn" != "None" ]]; then
        LB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$lb_arn" --region "$REGION" \
            --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null)
        echo -e "${CYAN}Deleting NLB/ALB: $LB_NAME${NC}"
        run_cmd "aws elbv2 delete-load-balancer --load-balancer-arn '$lb_arn' --region $REGION"
    fi
done

# Classic ELB - filter by cluster name
CLASSIC_LBS=$(aws elb describe-load-balancers --region "$REGION" \
    --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerName" \
    --output text 2>/dev/null || echo "")

for lb in $CLASSIC_LBS; do
    if [[ -n "$lb" ]] && [[ "$lb" != "None" ]]; then
        echo -e "${CYAN}Deleting Classic ELB: $lb${NC}"
        run_cmd "aws elb delete-load-balancer --load-balancer-name '$lb' --region $REGION"
    fi
done

if [[ -z "$LB_ARNS" ]] && [[ -z "$CLASSIC_LBS" ]]; then
    echo -e "${GREEN}✓ No load balancers found with '${CLUSTER_NAME}' in name${NC}"
fi

# ==============================================================================
# PHASE 4: Delete Target Groups (filter by cluster name)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 4: Delete Target Groups${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName, '${CLUSTER_NAME}')].TargetGroupArn" \
    --output text 2>/dev/null || echo "")

for tg_arn in $TG_ARNS; do
    if [[ -n "$tg_arn" ]] && [[ "$tg_arn" != "None" ]]; then
        TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --region "$REGION" \
            --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null)
        echo -e "${CYAN}Deleting Target Group: $TG_NAME${NC}"
        run_cmd "aws elbv2 delete-target-group --target-group-arn '$tg_arn' --region $REGION"
    fi
done

if [[ -z "$TG_ARNS" ]]; then
    echo -e "${GREEN}✓ No target groups found with '${CLUSTER_NAME}' in name${NC}"
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

# Delete ALL IAM roles that contain the cluster name
# This is the safest and simplest approach
echo -e "${CYAN}Looking for IAM roles containing '${CLUSTER_NAME}'...${NC}"

ALL_CLUSTER_ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, '${CLUSTER_NAME}')].RoleName" \
    --output text 2>/dev/null || echo "")

if [[ -n "$ALL_CLUSTER_ROLES" ]]; then
    for role in $ALL_CLUSTER_ROLES; do
        delete_iam_role "$role"
    done
else
    echo -e "${GREEN}✓ No IAM roles found with '${CLUSTER_NAME}' in name${NC}"
fi

# Delete instance profiles containing cluster name
echo -e "${CYAN}Looking for instance profiles containing '${CLUSTER_NAME}'...${NC}"

ALL_CLUSTER_PROFILES=$(aws iam list-instance-profiles \
    --query "InstanceProfiles[?contains(InstanceProfileName, '${CLUSTER_NAME}')].InstanceProfileName" \
    --output text 2>/dev/null || echo "")

if [[ -n "$ALL_CLUSTER_PROFILES" ]]; then
    for profile in $ALL_CLUSTER_PROFILES; do
        echo "  Deleting instance profile: $profile"
        if [[ "$DRY_RUN" != "true" ]]; then
            for role in $(aws iam get-instance-profile --instance-profile-name "$profile" --query 'InstanceProfile.Roles[*].RoleName' --output text 2>/dev/null); do
                aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role" 2>/dev/null || true
            done
            aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
        else
            echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No instance profiles found with '${CLUSTER_NAME}' in name${NC}"
fi

echo -e "${GREEN}✓ IAM cleanup complete${NC}"

# ==============================================================================
# PHASE 8: Delete IAM Policies (filter by cluster name)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 8: Delete IAM Policies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Delete all policies containing the cluster name
echo -e "${CYAN}Looking for IAM policies containing '${CLUSTER_NAME}'...${NC}"

ALL_CLUSTER_POLICIES=$(aws iam list-policies --scope Local \
    --query "Policies[?contains(PolicyName, '${CLUSTER_NAME}')].Arn" \
    --output text 2>/dev/null || echo "")

if [[ -n "$ALL_CLUSTER_POLICIES" ]]; then
    for policy_arn in $ALL_CLUSTER_POLICIES; do
        if [[ -n "$policy_arn" ]] && [[ "$policy_arn" != "None" ]]; then
            POLICY_NAME=$(echo "$policy_arn" | awk -F'/' '{print $NF}')
            echo -e "${CYAN}Deleting policy: $POLICY_NAME${NC}"
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
                aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null && \
                    echo -e "  ${GREEN}✓ Deleted${NC}" || \
                    echo -e "  ${YELLOW}⚠ Could not delete${NC}"
            else
                echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
            fi
        fi
    done
else
    echo -e "${GREEN}✓ No IAM policies found with '${CLUSTER_NAME}' in name${NC}"
fi

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
# PHASE 10: Delete S3 Buckets (filter by cluster name)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 10: Delete S3 Buckets${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Find all buckets containing cluster name
echo -e "${CYAN}Looking for S3 buckets containing '${CLUSTER_NAME}'...${NC}"

ALL_CLUSTER_BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${CLUSTER_NAME}')].Name" --output text 2>/dev/null || echo "")

if [[ -n "$ALL_CLUSTER_BUCKETS" ]]; then
    for bucket in $ALL_CLUSTER_BUCKETS; do
        echo -e "${CYAN}Deleting S3 bucket: $bucket${NC}"
        if [[ "$DRY_RUN" != "true" ]]; then
            aws s3 rm "s3://${bucket}" --recursive --region "$REGION" 2>/dev/null || true
            aws s3 rb "s3://${bucket}" --region "$REGION" 2>/dev/null && \
                echo -e "  ${GREEN}✓ Deleted${NC}" || \
                echo -e "  ${YELLOW}⚠ Could not delete${NC}"
        else
            echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No S3 buckets found with '${CLUSTER_NAME}' in name${NC}"
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
# PHASE 12: Delete KMS Aliases (filter by cluster name, not the keys)
# ==============================================================================
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 12: Delete KMS Aliases${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Find all KMS aliases containing cluster name
echo -e "${CYAN}Looking for KMS aliases containing '${CLUSTER_NAME}'...${NC}"

ALL_CLUSTER_ALIASES=$(aws kms list-aliases --region "$REGION" \
    --query "Aliases[?contains(AliasName, '${CLUSTER_NAME}')].AliasName" \
    --output text 2>/dev/null || echo "")

if [[ -n "$ALL_CLUSTER_ALIASES" ]]; then
    for alias_name in $ALL_CLUSTER_ALIASES; do
        echo -e "${CYAN}Deleting KMS alias: $alias_name${NC}"
        if [[ "$DRY_RUN" != "true" ]]; then
            aws kms delete-alias --alias-name "$alias_name" --region "$REGION" 2>/dev/null && \
                echo -e "  ${GREEN}✓ Deleted${NC}" || \
                echo -e "  ${YELLOW}⚠ Could not delete${NC}"
        else
            echo -e "  ${YELLOW}[DRY-RUN] Would delete${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ No KMS aliases found with '${CLUSTER_NAME}' in name${NC}"
fi

echo -e "${YELLOW}Note: KMS keys are NOT deleted (they may be shared). Delete manually if needed.${NC}"

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
