#!/bin/bash
# ==============================================================================
# Verify Cluster Script - Check cluster security and health
# ==============================================================================
# This script verifies:
# 1. Cluster Nodes status
# 2. Cluster Operators health
# 3. EC2 Instances with Cluster Tag
# 4. IMDSv2 Enforcement on all nodes
# 5. KMS Encryption on EBS volumes
# 6. AMI Encryption status
# 7. KMS Key Policy principals
#
# Usage: ./verify-cluster.sh [tfvars-file]
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration - Auto-detect or set manually
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Accept tfvars file as argument
TFVARS_FILE="${1:-env/demo.tfvars}"

# Try to get values from tfvars
if [[ -f "$TFVARS_FILE" ]]; then
    CLUSTER_NAME=$(grep '^cluster_name' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    INFRA_RANDOM_ID=$(grep '^infra_random_id' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    REGION=$(grep '^region' "$TFVARS_FILE" | awk -F'"' '{print $2}')
    KMS_ALIAS=$(grep '^kms_ec2_alias' "$TFVARS_FILE" | awk -F'"' '{print $2}')
else
    echo -e "${YELLOW}Warning: $TFVARS_FILE not found, using defaults${NC}"
fi

# Defaults if not found
CLUSTER_NAME="${CLUSTER_NAME:-my-ocp-cluster}"
INFRA_RANDOM_ID="${INFRA_RANDOM_ID:-d44a5}"
REGION="${REGION:-eu-west-3}"
KMS_ALIAS="${KMS_ALIAS:-alias/ec2-ebs}"

# Build infra ID - if INFRA_RANDOM_ID already contains cluster name, use as-is
if [[ "$INFRA_RANDOM_ID" == *"$CLUSTER_NAME"* ]]; then
    INFRA_ID="$INFRA_RANDOM_ID"
else
    INFRA_ID="${CLUSTER_NAME}-${INFRA_RANDOM_ID}"
fi

CLUSTER_TAG="kubernetes.io/cluster/${INFRA_ID}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           OpenShift Cluster Verification                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}Configuration:${NC}"
echo "  Cluster Name:    $CLUSTER_NAME"
echo "  Infra ID:        $INFRA_ID"
echo "  Region:          $REGION"
echo "  Cluster Tag:     $CLUSTER_TAG"
echo "  KMS Alias:       $KMS_ALIAS"
echo "  TFVars File:     $TFVARS_FILE"
echo

# === 1. Cluster Nodes ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}1. Cluster Nodes${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    oc get nodes -o wide
    echo
    NODE_COUNT=$(oc get nodes --no-headers | wc -l)
    READY_COUNT=$(oc get nodes --no-headers | grep -c "Ready" || echo "0")
    echo -e "Total Nodes: $NODE_COUNT, Ready: $READY_COUNT"
    if [[ "$NODE_COUNT" == "$READY_COUNT" ]]; then
        echo -e "${GREEN}✓ All nodes are Ready${NC}"
    else
        echo -e "${RED}✗ Some nodes are not Ready${NC}"
    fi
else
    echo -e "${YELLOW}⚠ oc not available or not logged in, skipping node check${NC}"
fi
echo

# === 2. Cluster Operators ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}2. Cluster Operators${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    DEGRADED=$(oc get co --no-headers | grep -c "True$" || echo "0")
    UNAVAILABLE=$(oc get co --no-headers | awk '{print $3}' | grep -c "False" || echo "0")
    TOTAL_CO=$(oc get co --no-headers | wc -l)
    
    echo "Total Operators: $TOTAL_CO"
    echo "Degraded: $DEGRADED"
    echo "Unavailable: $UNAVAILABLE"
    
    if [[ "$DEGRADED" == "0" ]] && [[ "$UNAVAILABLE" == "0" ]]; then
        echo -e "${GREEN}✓ All cluster operators are healthy${NC}"
    else
        echo -e "${YELLOW}⚠ Some operators need attention:${NC}"
        oc get co | grep -E "False|True$" | grep -v "True.*False.*False"
    fi
else
    echo -e "${YELLOW}⚠ oc not available or not logged in, skipping operator check${NC}"
fi
echo

# === 3. EC2 Instances ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}3. EC2 Instances (Cluster Name: ${CLUSTER_NAME})${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Search by name pattern (more reliable)
aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[?Tags[?Key=='Name' && contains(Value, '${CLUSTER_NAME}')]].[InstanceId,InstanceType,PrivateIpAddress,Tags[?Key=='Name'].Value|[0]]" \
    --output table --region "$REGION" 2>/dev/null || echo -e "${YELLOW}⚠ Could not query EC2 instances${NC}"

INSTANCE_COUNT=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[?Tags[?Key=='Name' && contains(Value, '${CLUSTER_NAME}')]].InstanceId" \
    --output text --region "$REGION" 2>/dev/null | wc -w)
echo
echo -e "Running instances with '${CLUSTER_NAME}' in name: $INSTANCE_COUNT"
echo

# === 4. IMDSv2 Enforcement Check ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}4. IMDSv2 Enforcement on All Nodes${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Get all running instances with cluster name in their Name tag
IMDS_DATA=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[?Tags[?Key=='Name' && contains(Value, '${CLUSTER_NAME}')]].[InstanceId,Tags[?Key=='Name'].Value|[0],MetadataOptions.HttpTokens]" \
    --output text --region "$REGION" 2>/dev/null | grep -v "^$")

if [[ -n "$IMDS_DATA" ]]; then
    TOTAL_INSTANCES=0
    IMDSV2_ENFORCED=0
    IMDSV2_OPTIONAL=0
    
    echo "Instance ID          | Name                                      | IMDSv2"
    echo "---------------------|-------------------------------------------|----------"
    
    while IFS=$'\t' read -r instance_id instance_name http_tokens; do
        [[ -z "$instance_id" ]] && continue
        ((TOTAL_INSTANCES++))
        
        # Truncate name if too long
        DISPLAY_NAME="${instance_name:0:41}"
        
        if [[ "$http_tokens" == "required" ]]; then
            ((IMDSV2_ENFORCED++))
            STATUS="${GREEN}required${NC}"
        else
            ((IMDSV2_OPTIONAL++))
            STATUS="${RED}optional${NC}"
        fi
        
        printf "%-20s | %-41s | %b\n" "$instance_id" "$DISPLAY_NAME" "$STATUS"
    done <<< "$IMDS_DATA"
    
    echo
    echo "Total Instances: $TOTAL_INSTANCES"
    echo "IMDSv2 Enforced (required): $IMDSV2_ENFORCED"
    echo "IMDSv2 Optional: $IMDSV2_OPTIONAL"
    echo
    
    if [[ "$TOTAL_INSTANCES" -eq "$IMDSV2_ENFORCED" ]]; then
        echo -e "${GREEN}✓ All nodes have IMDSv2 enforced (HttpTokens=required)${NC}"
    else
        echo -e "${RED}✗ WARNING: $IMDSV2_OPTIONAL node(s) do NOT have IMDSv2 enforced!${NC}"
        echo -e "${YELLOW}  Recommendation: Update MetadataOptions.HttpTokens to 'required' for security${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No instances found with '${CLUSTER_NAME}' in name${NC}"
    echo "  Trying alternative search by cluster tag..."
    
    # Fallback: try by tag
    aws ec2 describe-instances \
        --filters "Name=tag:${CLUSTER_TAG},Values=owned" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],MetadataOptions.HttpTokens]' \
        --output table --region "$REGION" 2>/dev/null || echo -e "${YELLOW}⚠ Could not query instances${NC}"
fi
echo

# === 5. KMS Encryption on EBS Volumes ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}5. KMS Encryption on EBS Volumes${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Get expected KMS key ARN
EXPECTED_KMS_ARN=$(aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" \
    --query 'KeyMetadata.Arn' --output text 2>/dev/null || echo "NOT_FOUND")
echo "Expected KMS Key: $EXPECTED_KMS_ARN"
echo

# Get instance IDs for this cluster
CLUSTER_INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[?Tags[?Key=='Name' && contains(Value, '${CLUSTER_NAME}')]].InstanceId" \
    --output text --region "$REGION" 2>/dev/null)

# Get volumes attached to cluster instances
VOLUMES=""
for iid in $CLUSTER_INSTANCE_IDS; do
    VOL_DATA=$(aws ec2 describe-volumes \
        --filters "Name=attachment.instance-id,Values=$iid" \
        --query 'Volumes[*].[VolumeId,Encrypted,KmsKeyId]' \
        --output text --region "$REGION" 2>/dev/null)
    VOLUMES="${VOLUMES}${VOL_DATA}"$'\n'
done

if [[ -n "$VOLUMES" ]]; then
    TOTAL_VOLS=0
    ENCRYPTED_VOLS=0
    CORRECT_KEY_VOLS=0
    
    while read -r vol_id encrypted kms_key; do
        ((TOTAL_VOLS++))
        if [[ "$encrypted" == "True" ]]; then
            ((ENCRYPTED_VOLS++))
            if [[ "$kms_key" == "$EXPECTED_KMS_ARN" ]]; then
                ((CORRECT_KEY_VOLS++))
            fi
        fi
    done <<< "$VOLUMES"
    
    echo "Total Volumes: $TOTAL_VOLS"
    echo "Encrypted: $ENCRYPTED_VOLS"
    echo "Using Correct CMK: $CORRECT_KEY_VOLS"
    echo
    
    if [[ "$TOTAL_VOLS" == "$ENCRYPTED_VOLS" ]] && [[ "$TOTAL_VOLS" == "$CORRECT_KEY_VOLS" ]]; then
        echo -e "${GREEN}✓ All volumes are encrypted with the correct CMK${NC}"
    elif [[ "$TOTAL_VOLS" == "$ENCRYPTED_VOLS" ]]; then
        echo -e "${YELLOW}⚠ All volumes encrypted, but some use different KMS keys${NC}"
    else
        echo -e "${RED}✗ Some volumes are not encrypted!${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No volumes found with cluster tag${NC}"
fi
echo

# === 6. AMI Encryption Status ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}6. AMI Encryption Status${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    AMI_ID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}' 2>/dev/null)
    if [[ -n "$AMI_ID" ]]; then
        echo "AMI ID: $AMI_ID"
        
        AMI_INFO=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$REGION" \
            --query 'Images[0].{Name:Name,Encrypted:BlockDeviceMappings[0].Ebs.Encrypted,SnapshotId:BlockDeviceMappings[0].Ebs.SnapshotId}' \
            --output json 2>/dev/null)
        
        AMI_NAME=$(echo "$AMI_INFO" | jq -r '.Name')
        AMI_ENCRYPTED=$(echo "$AMI_INFO" | jq -r '.Encrypted')
        SNAPSHOT_ID=$(echo "$AMI_INFO" | jq -r '.SnapshotId')
        
        echo "AMI Name: $AMI_NAME"
        echo "AMI Encrypted: $AMI_ENCRYPTED"
        
        if [[ -n "$SNAPSHOT_ID" ]] && [[ "$SNAPSHOT_ID" != "null" ]]; then
            SNAPSHOT_KMS=$(aws ec2 describe-snapshots --snapshot-ids "$SNAPSHOT_ID" --region "$REGION" \
                --query 'Snapshots[0].KmsKeyId' --output text 2>/dev/null)
            echo "Snapshot KMS Key: $SNAPSHOT_KMS"
            
            if [[ "$AMI_ENCRYPTED" == "true" ]] && [[ "$SNAPSHOT_KMS" == "$EXPECTED_KMS_ARN" ]]; then
                echo -e "${GREEN}✓ AMI is encrypted with the correct CMK${NC}"
            elif [[ "$AMI_ENCRYPTED" == "true" ]]; then
                echo -e "${YELLOW}⚠ AMI is encrypted but with a different KMS key${NC}"
            else
                echo -e "${RED}✗ AMI is not encrypted${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Could not get AMI ID from MachineSet${NC}"
    fi
else
    echo -e "${YELLOW}⚠ oc not available, skipping AMI check${NC}"
fi
echo

# === 7. KMS Key Policy ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}7. KMS Key Policy - Authorized Roles${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

KMS_KEY_ID=$(aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" \
    --query 'KeyMetadata.KeyId' --output text 2>/dev/null)

if [[ -n "$KMS_KEY_ID" ]] && [[ "$KMS_KEY_ID" != "None" ]]; then
    echo "KMS Key ID: $KMS_KEY_ID"
    echo
    echo "Authorized principals:"
    aws kms get-key-policy --key-id "$KMS_KEY_ID" --policy-name default --region "$REGION" \
        --query 'Policy' --output text 2>/dev/null | jq -r '.Statement[].Principal.AWS // .Statement[].Principal' | sort -u
else
    echo -e "${YELLOW}⚠ Could not get KMS key policy${NC}"
fi
echo

# === Summary ===
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${GREEN}Verification complete!${NC}"
echo
echo "Console URL:"
if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    oc whoami --show-console 2>/dev/null || echo "  (run 'oc whoami --show-console' when logged in)"
fi
echo
