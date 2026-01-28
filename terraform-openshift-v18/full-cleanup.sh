#!/bin/bash
# ==============================================================================
# Full Cleanup Script - Remove all local files and optionally AWS resources
# ==============================================================================
# This script performs a complete cleanup of the OpenShift installation:
# 1. Removes all local Terraform state and cache
# 2. Removes OpenShift installer files
# 3. Removes ccoctl output
# 4. Removes logs
# 5. Optionally destroys AWS resources
#
# Usage: 
#   ./full-cleanup.sh                    # Local files only
#   ./full-cleanup.sh --with-aws-destroy # Also destroy AWS resources
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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Full OpenShift Installation Cleanup                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if AWS destroy is requested
AWS_DESTROY=false
if [[ "$1" == "--with-aws-destroy" ]]; then
    AWS_DESTROY=true
fi

# Warning
echo -e "${YELLOW}⚠ WARNING: This will delete all local installation files!${NC}"
echo
echo "The following will be removed:"
echo "  • Terraform state and cache (.terraform/, terraform.tfstate*)"
echo "  • OpenShift installer files (installer-files/)"
echo "  • CCOCTL output (output/)"
echo "  • Initial setup backup (init_setup/)"
echo "  • Installation logs (*.log)"
if [[ "$AWS_DESTROY" == "true" ]]; then
    echo -e "${RED}  • Route53 DNS records (api, api-int, *.apps)${NC}"
    echo -e "${RED}  • AWS resources (via terraform destroy)${NC}"
fi
echo

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Starting cleanup...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Function to remove directory/file
remove_item() {
    local item=$1
    local description=$2
    
    if [[ -e "$item" ]]; then
        echo -e "${CYAN}Removing: ${description}${NC}"
        rm -rf "$item"
        echo -e "${GREEN}✓ Removed: ${item}${NC}"
    else
        echo -e "${YELLOW}⚠ Not found (already removed): ${item}${NC}"
    fi
}

# Step 1: AWS Resources (if requested)
if [[ "$AWS_DESTROY" == "true" ]]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Step 1: Destroying AWS Resources${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
    
    # Use the comprehensive destroy script if available
    if [[ -f "destroy-cluster.sh" ]]; then
        echo -e "${CYAN}Running comprehensive destroy-cluster.sh...${NC}"
        chmod +x destroy-cluster.sh
        ./destroy-cluster.sh --auto-approve || echo -e "${YELLOW}⚠ Destroy script had errors (continuing with local cleanup)${NC}"
    else
        # Fallback to manual cleanup
        echo -e "${CYAN}Step 1a: Deleting Route53 DNS records...${NC}"
        if [[ -f "env/demo.tfvars" ]]; then
            # Parse values from demo.tfvars
            HOSTED_ZONE=$(grep '^hosted_zone' env/demo.tfvars | awk -F'"' '{print $2}')
            CLUSTER_NAME=$(grep '^cluster_name' env/demo.tfvars | awk -F'"' '{print $2}')
            DOMAIN=$(grep '^domain' env/demo.tfvars | awk -F'"' '{print $2}')
            
            if [[ -n "$HOSTED_ZONE" ]] && [[ -n "$CLUSTER_NAME" ]] && [[ -n "$DOMAIN" ]]; then
                if [[ -f "delete-record.sh" ]]; then
                    chmod +x delete-record.sh
                    ./delete-record.sh "$HOSTED_ZONE" "api.$CLUSTER_NAME.$DOMAIN" 2>/dev/null || true
                    ./delete-record.sh "$HOSTED_ZONE" "api-int.$CLUSTER_NAME.$DOMAIN" 2>/dev/null || true
                    ./delete-record.sh "$HOSTED_ZONE" "*.apps.$CLUSTER_NAME.$DOMAIN" 2>/dev/null || true
                fi
            fi
        fi
        
        # Step 1b: Delete old OIDC roles
        echo -e "${CYAN}Step 1b: Deleting old OIDC roles...${NC}"
        CLUSTER_NAME=$(grep '^cluster_name' env/demo.tfvars 2>/dev/null | awk -F'"' '{print $2}')
        if [[ -n "$CLUSTER_NAME" ]]; then
            for role in $(aws iam list-roles --query "Roles[?contains(RoleName,'${CLUSTER_NAME}-openshift')].RoleName" --output text 2>/dev/null); do
                for policy in $(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null); do
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                done
                for policy_arn in $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
                done
                aws iam delete-role --role-name "$role" 2>/dev/null || true
            done
        fi

        # Step 1c: Destroy Cluster
        echo -e "${CYAN}Step 1c: Destroying OpenShift cluster...${NC}"
        if [[ -f "delete-cluster.sh" ]]; then
            chmod +x delete-cluster.sh
            ./delete-cluster.sh || true
        fi
    fi
    echo
fi

# Step 2: Terraform Files
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2: Removing Terraform State and Cache${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
remove_item ".terraform/" "Terraform cache directory"
remove_item ".terraform.lock.hcl" "Terraform lock file"
remove_item "terraform.tfstate" "Terraform state file"
remove_item "terraform.tfstate.backup" "Terraform state backup"
remove_item "terraform.tfstate.broken" "Broken state file"
remove_item ".terraform.tfstate.lock.info" "State lock info"
echo

# Step 3: OpenShift Installer Files
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3: Removing OpenShift Installer Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
remove_item "installer-files/" "OpenShift installer files directory"
remove_item "init_setup/" "Initial setup backup directory"
echo

# Step 4: CCOCTL Output
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 4: Removing CCOCTL Output${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
remove_item "output/" "CCOCTL output directory"
echo

# Step 5: Log Files
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 5: Removing Log Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
remove_item "openshift-install.log" "OpenShift installer log"
remove_item ".openshift_install.log" "Hidden installer log"
remove_item "terraform.log" "Terraform log"
remove_item "*.log" "All log files"
remove_item "kms-policy.json" "KMS policy file"
remove_item "tfplan" "Terraform plan file"
remove_item "dns-*.json" "DNS change batch files"
remove_item "trust-policy*.json" "IAM trust policy files"
echo

# Step 6: Backup Files
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 6: Removing Backup Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
for backup_file in *.backup *~; do
    if [[ -f "$backup_file" ]]; then
        remove_item "$backup_file" "Backup file"
    fi
done
echo

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Cleanup Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${GREEN}✓ Local files cleaned successfully!${NC}"
echo

# List remaining files
echo -e "${CYAN}Remaining files in directory:${NC}"
ls -la | grep -v "^total" | tail -n +4 | head -20
echo

if [[ "$AWS_DESTROY" == "true" ]]; then
    echo -e "${YELLOW}Note: AWS resources destruction was attempted, including:${NC}"
    echo -e "${YELLOW}  • Route53 DNS records${NC}"
    echo -e "${YELLOW}  • OpenShift cluster resources${NC}"
    echo -e "${YELLOW}Verify manually if all resources were removed.${NC}"
    echo
fi

echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo
echo -e "${CYAN}Next steps:${NC}"
echo "1. Verify no AWS resources remain (if destroyed)"
echo "2. Run: terraform init"
echo "3. Run: terraform plan -var-file=env/demo.tfvars"
echo "4. Run: terraform apply -var-file=env/demo.tfvars"
echo
