# Terraform Variables - Complete Guide

## Quick Answers to Common Questions

### What is `hosted_zone`?

**Route53 Hosted Zone ID** - The DNS zone where OpenShift will create DNS records.

```bash
# Find your hosted zones
aws route53 list-hosted-zones

# Output example:
# {
#   "Id": "/hostedzone/Z1234567890ABC",
#   "Name": "example.com."
# }

# Use ONLY the ID part in tfvars:
hosted_zone = "Z1234567890ABC"
```

**What it creates**:
- `api.cluster-name.domain` → Points to control plane load balancer
- `*.apps.cluster-name.domain` → Points to ingress load balancer (after install)

---

### What is `route_default`?

**Ingress Load Balancer DNS name** - The AWS ELB created by OpenShift for application traffic.

**IMPORTANT**: Leave **EMPTY** for initial installation!

```hcl
# Initial install:
route_default = ""

# After install (Day 2):
route_default = "abc12345-1234567890.elb.eu-west-1.amazonaws.com"
```

**How to get it after installation**:
```bash
# Method 1: Using kubectl
kubectl get svc router-default -n openshift-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Method 2: Using oc
oc get svc router-default -n openshift-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Method 3: AWS CLI
aws elbv2 describe-load-balancers \
  --region eu-west-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `CLUSTER-NAME`)].DNSName'
```

**What it's used for**:
- Creates Route53 wildcard record: `*.apps.cluster-name.domain` → Ingress ELB
- Allows access to OpenShift console: `https://console-openshift-console.apps.cluster-name.domain`
- Routes all application traffic

---

### What is `kms_ec2_alias`?

**KMS Key for EBS Volume Encryption** - Customer-managed encryption key for all EBS volumes.

**MUST match the KMS key used when creating your custom AMI!**

See detailed guide below: [How to Create KMS Key](#how-to-create-kms-key)

---

### What are IAM role names?

**IAM roles for OpenShift nodes** - Created automatically by Terraform.

```hcl
control_plane_role_name   = "ocp-demo-controlplane"
aws_iam_role_compute_node = "ocp-demo-compute"
aws_worker_iam_role       = "ocp-demo-worker"
```

**Important**: 
- You just **provide the names**
- **Terraform creates them automatically**
- DO NOT create them manually!
- Names must be unique in your AWS account

---

## How to Create KMS Key

### Prerequisites

```bash
# Ensure AWS CLI is configured
aws sts get-caller-identity

# Set your region
export AWS_REGION="eu-west-1"
```

---

### Option 1: Create New KMS Key (Recommended for New Deployments)

#### Step 1: Create the KMS Key

```bash
# Create a customer-managed KMS key
aws kms create-key \
  --description "OpenShift EBS Volume Encryption Key" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --region eu-west-1

# Output will show:
# {
#   "KeyMetadata": {
#     "KeyId": "12345678-1234-1234-1234-123456789012",
#     "Arn": "arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"
#   }
# }
```

**Save the KeyId** from the output!

#### Step 2: Create an Alias (Human-Readable Name)

```bash
# Create alias for easy reference
aws kms create-alias \
  --alias-name alias/openshift-ebs-encryption \
  --target-key-id 12345678-1234-1234-1234-123456789012 \
  --region eu-west-1
```

**Replace `12345678-1234-1234-1234-123456789012` with your actual KeyId!**

#### Step 3: Add Tags (Optional but Recommended)

```bash
# Tag the key for identification
aws kms tag-resource \
  --key-id 12345678-1234-1234-1234-123456789012 \
  --tags TagKey=Name,TagValue=OpenShift-EBS-Encryption \
         TagKey=Purpose,TagValue=OpenShift-Volume-Encryption \
         TagKey=Environment,TagValue=Production \
         TagKey=ManagedBy,TagValue=Terraform \
  --region eu-west-1
```

#### Step 4: Grant vmimport Role Access (CRITICAL!)

**Required if you created a custom AMI with KMS encryption:**

```bash
# Grant vmimport role permission to use this KMS key
aws kms create-grant \
  --key-id 12345678-1234-1234-1234-123456789012 \
  --grantee-principal arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/vmimport \
  --operations Encrypt Decrypt GenerateDataKey GenerateDataKeyWithoutPlaintext CreateGrant DescribeKey \
  --region eu-west-1

echo "✓ vmimport role granted access to KMS key"
```

#### Step 5: Use in tfvars

```hcl
# Use the alias in your tfvars file
kms_ec2_alias = "alias/openshift-ebs-encryption"
```

---

### Option 2: Use Existing KMS Key

#### Find Existing KMS Keys

```bash
# List all KMS keys (detailed)
aws kms list-keys --region eu-west-1

# List aliases (easier to read)
aws kms list-aliases --region eu-west-1

# Filter for specific alias
aws kms list-aliases --region eu-west-1 | grep "plaasma"

# Output example:
# {
#   "Aliases": [
#     {
#       "AliasName": "alias/plaasma-ec2-cmk",
#       "TargetKeyId": "12345678-1234-1234-1234-123456789012"
#     }
#   ]
# }
```

#### Verify Key Details

```bash
# Describe specific key
aws kms describe-key \
  --key-id alias/plaasma-ec2-cmk \
  --region eu-west-1

# Check who can use the key
aws kms get-key-policy \
  --key-id alias/plaasma-ec2-cmk \
  --policy-name default \
  --region eu-west-1
```

#### Use in tfvars

```hcl
# Use existing alias
kms_ec2_alias = "alias/plaasma-ec2-cmk"
```

---

### Complete Automated Script

Save as `create-kms-key.sh`:

```bash
#!/bin/bash
set -e

# Configuration
REGION="eu-west-1"
ALIAS_NAME="alias/openshift-ebs-demo"
DESCRIPTION="OpenShift Demo Cluster EBS Encryption"

echo "=========================================="
echo "Creating KMS Key for OpenShift"
echo "=========================================="
echo ""

# Create KMS key
echo "Step 1: Creating KMS key..."
KEY_OUTPUT=$(aws kms create-key \
  --description "$DESCRIPTION" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --region $REGION)

KEY_ID=$(echo $KEY_OUTPUT | jq -r '.KeyMetadata.KeyId')
KEY_ARN=$(echo $KEY_OUTPUT | jq -r '.KeyMetadata.Arn')

echo "✓ KMS Key created!"
echo "  Key ID:  $KEY_ID"
echo "  Key ARN: $KEY_ARN"
echo ""

# Create alias
echo "Step 2: Creating alias..."
aws kms create-alias \
  --alias-name $ALIAS_NAME \
  --target-key-id $KEY_ID \
  --region $REGION

echo "✓ Alias created: $ALIAS_NAME"
echo ""

# Add tags
echo "Step 3: Adding tags..."
aws kms tag-resource \
  --key-id $KEY_ID \
  --tags TagKey=Name,TagValue=OpenShift-Demo-EBS \
         TagKey=ManagedBy,TagValue=Manual \
         TagKey=Purpose,TagValue=EBS-Encryption \
         TagKey=CreatedDate,TagValue=$(date +%Y-%m-%d) \
  --region $REGION

echo "✓ Tags added"
echo ""

# Grant vmimport access
echo "Step 4: Granting vmimport role access..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws kms create-grant \
  --key-id $KEY_ID \
  --grantee-principal arn:aws:iam::${ACCOUNT_ID}:role/vmimport \
  --operations Encrypt Decrypt GenerateDataKey GenerateDataKeyWithoutPlaintext CreateGrant DescribeKey \
  --region $REGION 2>/dev/null || echo "⚠ Warning: vmimport role may not exist yet (this is OK if you haven't created custom AMI)"

echo "✓ Grant created (if vmimport role exists)"
echo ""

# Summary
echo "=========================================="
echo "KMS Key Setup Complete!"
echo "=========================================="
echo "Key ID:       $KEY_ID"
echo "Key ARN:      $KEY_ARN"
echo "Alias:        $ALIAS_NAME"
echo "Region:       $REGION"
echo ""
echo "Next steps:"
echo "1. Add to your tfvars:"
echo "   kms_ec2_alias = \"$ALIAS_NAME\""
echo ""
echo "2. Use this key when creating custom AMI"
echo ""
echo "3. Verify key exists:"
echo "   aws kms describe-key --key-id $ALIAS_NAME --region $REGION"
echo "=========================================="
```

**Make executable and run**:
```bash
chmod +x create-kms-key.sh
./create-kms-key.sh
```

---

### Verification

#### Check KMS Key Exists

```bash
# List aliases
aws kms list-aliases --region eu-west-1 | grep "openshift"

# Describe key
aws kms describe-key \
  --key-id alias/openshift-ebs-encryption \
  --region eu-west-1

# Should show:
# - KeyState: Enabled
# - KeyUsage: ENCRYPT_DECRYPT
# - Enabled: true
```

#### Test Encryption/Decryption

```bash
# Encrypt test data
aws kms encrypt \
  --key-id alias/openshift-ebs-encryption \
  --plaintext "test" \
  --region eu-west-1

# If successful, key is working!
```

---

### Three Formats Accepted in tfvars

```hcl
# Format 1: Alias (RECOMMENDED - human-readable)
kms_ec2_alias = "alias/openshift-ebs-encryption"

# Format 2: Key ID
kms_ec2_alias = "12345678-1234-1234-1234-123456789012"

# Format 3: Full ARN
kms_ec2_alias = "arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"
```

**Best Practice**: Use **alias format** - easier to manage and remember!

---

### Important Notes

#### For Custom AMI Creation

If you're using a custom AMI with KMS encryption (from Part 1):

1. **Use the SAME KMS key** for both AMI and tfvars
2. **vmimport role must have access** to the key
3. Get the key from your AMI creation:
   ```bash
   source custom-ami-build/custom-ami-result.env
   echo $KMS_KEY_ID
   ```

#### Key Rotation (Optional)

```bash
# Enable automatic key rotation (yearly)
aws kms enable-key-rotation \
  --key-id alias/openshift-ebs-encryption \
  --region eu-west-1

# Check rotation status
aws kms get-key-rotation-status \
  --key-id alias/openshift-ebs-encryption \
  --region eu-west-1
```

#### Key Policy (Advanced)

By default, the key is accessible to your AWS account root. To restrict access:

```bash
# Get current policy
aws kms get-key-policy \
  --key-id alias/openshift-ebs-encryption \
  --policy-name default \
  --region eu-west-1 > kms-policy.json

# Edit kms-policy.json as needed

# Update policy
aws kms put-key-policy \
  --key-id alias/openshift-ebs-encryption \
  --policy-name default \
  --policy file://kms-policy.json \
  --region eu-west-1
```

---

## Complete Variable Reference

### 1. AWS Account Variables

| Variable | Required | Description | How to Find |
|----------|----------|-------------|-------------|
| `account_id` | Yes | AWS account ID (12 digits) | `aws sts get-caller-identity` |
| `region` | Yes | AWS region | Your chosen region |
| `vpc_id` | Yes | Existing VPC ID | `aws ec2 describe-vpcs` |
| `ccoe_boundary` | Optional | IAM permission boundary | `aws iam list-policies` or ask admin |

### 2. OpenShift Release Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `release_image` | Yes | OpenShift version to install | `quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64` |
| `openshift_ssh_key` | Optional | SSH key for node access | `ssh-rsa AAAAB3...` |

**For Disconnected/Air-gapped**:
```hcl
release_image = "your-registry.company.com/ocp-release:4.16.9-x86_64"
```

### 3. DNS Variables

| Variable | Required | Description | Format |
|----------|----------|-------------|--------|
| `domain` | Yes | Base domain for cluster | `example.com` |
| `hosted_zone` | Yes | Route53 zone ID | `Z1234567890ABC` |
| `route_default` | Day 2 | Ingress ELB DNS (empty initially) | `abc-123.elb.eu-west-1.amazonaws.com` |

**DNS Records Created**:
- `api.cluster-name.domain` → Control plane API (6443)
- `*.apps.cluster-name.domain` → Application ingress (80, 443)

### 4. AMI Variables

| Variable | Required | Description | Source |
|----------|----------|-------------|--------|
| `ami` | Yes | Custom RHCOS AMI with KMS | `custom-ami-result.env` |
| `aws_worker_iam_id` | Yes | Same as `ami` | Same value |
| `kms_ec2_alias` | Yes | KMS key for encryption | `alias/your-key` |

```bash
# Get your AMI ID
source custom-ami-build/custom-ami-result.env
echo $CUSTOM_AMI
```

### 5. Network CIDR Variables

| Variable | Default | Purpose | When to Change |
|----------|---------|---------|----------------|
| `service_network_cidr` | `172.30.0.0/16` | Internal k8s services | Rarely (only if conflicts) |
| `machine_network_cidr` | Your VPC CIDR | Node IP range | **Must match VPC!** |
| `cluster_network_cidr` | `10.128.0.0/14` | Pod IP range | Rarely (only if conflicts) |
| `cluster_network_host_prefix` | `23` | IPs per node (512) | Rarely |

**How to check your VPC CIDR**:
```bash
aws ec2 describe-vpcs --vpc-ids vpc-xxx --query 'Vpcs[0].CidrBlock'
```

### 6. Subnet Variables

| Variable | Required | Description | Important Notes |
|----------|----------|-------------|-----------------|
| `aws_worker_availability_zones` | Yes | List of AZs | Need at least 3 for HA |
| `aws_private_subnets` | Yes | Private subnet IDs | One per AZ, PRIVATE only (with NAT) |

**Requirements**:
- Must be **PRIVATE** subnets (no direct internet gateway)
- Must have **NAT Gateway** for internet access
- Must span **at least 3 AZs** for high availability
- Must have enough IPs for all nodes

```bash
# Find your private subnets
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'Subnets[?MapPublicIpOnLaunch==`false`].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

### 7. Pull Secret & Installer

| Variable | Required | Description |
|----------|----------|-------------|
| `openshift_pull_secret` | Yes | Path to pull secret JSON |
| `openshift_installer_url` | Legacy | NOT USED (kept for compatibility) |

**Download pull secret**: https://console.redhat.com/openshift/install/pull-secret

### 8. Proxy Variables (Optional)

```hcl
proxy_config = {
  enabled    = false  # true if using proxy
  httpProxy  = "http://proxy:8080"
  httpsProxy = "http://proxy:8080"
  noProxy    = "127.0.0.1,localhost,169.254.169.254,..."
}
```

**When to enable**:
- Connected with proxy: `enabled = true`
- Direct internet: `enabled = false`
- Disconnected/air-gapped: `enabled = false`

**Critical noProxy entries**:
- `169.254.169.254` - AWS metadata (REQUIRED!)
- `172.30.0.0/16` - Service network
- `10.128.0.0/14` - Pod network
- Your VPC CIDR
- AWS service endpoints for your region

### 9. Cluster Naming Variables

| Variable | Purpose | Rules | Example |
|----------|---------|-------|---------|
| `cluster_name` | Cluster identifier | Short, alphanumeric with hyphens | `demo`, `prod` |
| `infra_random_id` | InfraID suffix | Exactly 5 chars, lowercase a-z 0-9 | `abc12` |
| `s3_bucket_name_oidc` | OIDC bucket | Globally unique | `ocp-euw1-oidc-demo` |

**InfraID Format**: `cluster_name-infra_random_id`
- Example: `demo-abc12`
- This is what we made controllable!

### 10. IAM Role Names

**These are created automatically by Terraform - you just provide the names!**

All must be unique within your AWS account:

```hcl
control_plane_role_name   = "ocp-demo-controlplane"
aws_iam_role_compute_node = "ocp-demo-compute"
aws_worker_iam_role       = "ocp-demo-worker"
ocpcontrolplane_policy    = "ocp-demo-controlplane-policy"
ocpworkernode_policy      = "ocp-demo-worker-policy"
```

**Important**:
- ✅ You provide the names
- ✅ Terraform creates them
- ❌ DO NOT create manually!

### 11. Node Sizing Variables

#### Worker Nodes

| Variable | Recommended | Notes |
|----------|-------------|-------|
| `worker_count` | 3 | Minimum 2, odd number for HA |
| `aws_worker_instance_type` | `m5.2xlarge` | Based on workload |
| `aws_worker_root_volume_type` | `gp3` | gp3 for cost/performance |
| `aws_worker_root_volume_size` | `200` | Min 120GB, 200+ recommended |
| `aws_worker_root_volume_iops` | `3000` | gp3 baseline |

**Instance type guide**:
- Small: `m5.xlarge` (4 vCPU, 16GB)
- Medium: `m5.2xlarge` (8 vCPU, 32GB)
- Large: `m5.4xlarge` (16 vCPU, 64GB)

#### Infrastructure Nodes (Optional, Day 2)

| Variable | Initial | Production |
|----------|---------|------------|
| `aws_infra_count_per_availability_zone` | `0` | `1` |

**What infra nodes run**:
- Ingress router
- Monitoring (Prometheus)
- Logging
- Registry

**Set to 0 initially**, add later for production.

#### Control Plane Nodes

| Variable | Value | Why |
|----------|-------|-----|
| `master_count` | `3` | DO NOT CHANGE (etcd requires odd number) |
| `aws_master_instance_type` | `m5.2xlarge` | etcd needs good CPU/disk |
| `aws_master_volume_type` | `gp3` | Good IOPS for etcd |
| `aws_master_volume_iops` | `4000` | etcd database performance |

---

## Installation Workflow

### Phase 1: Prerequisites

1. **Create KMS Key** (see above)
2. **Create Custom AMI** (Part 1 - custom-ami-build)
3. **Build Custom Installer** (Part 2)
4. **Get Pull Secret** from Red Hat

### Phase 2: Fill tfvars

1. Copy demo.tfvars to my-cluster.tfvars
2. Fill in all required variables
3. **Leave `route_default` empty**

### Phase 3: Terraform Apply

```bash
cd terraform-openshift-v18

# Initialize
terraform init

# Plan
terraform plan -var-file="env/my-cluster.tfvars"

# Apply
terraform apply -var-file="env/my-cluster.tfvars"
```

**What happens**:
1. Creates IAM roles and policies
2. Generates SSH keys
3. Creates OIDC provider
4. Runs OpenShift installer
5. Creates DNS records (API endpoint)
6. Waits for cluster ready (~45 minutes)

### Phase 4: Get Ingress ELB (Day 2)

**After cluster is ready**:

```bash
# Get ingress ELB hostname
kubectl get svc router-default -n openshift-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Example output: abc12345-1234567890.elb.eu-west-1.amazonaws.com
```

### Phase 5: Update Route (Day 2)

1. Edit your tfvars:
```hcl
route_default = "abc12345-1234567890.elb.eu-west-1.amazonaws.com"
```

2. Apply again:
```bash
terraform apply -var-file="env/my-cluster.tfvars"
```

**This creates**: `*.apps.cluster-name.domain` → Ingress ELB

---

## Common Issues

### Issue: Can't find hosted_zone

```bash
# List all hosted zones
aws route53 list-hosted-zones

# Find specific zone
aws route53 list-hosted-zones | grep "your-domain.com"
```

### Issue: Don't know VPC CIDR

```bash
# Get VPC CIDR
aws ec2 describe-vpcs --vpc-ids vpc-xxx \
  --query 'Vpcs[0].CidrBlock' --output text
```

### Issue: Don't have permission boundary

Set to empty or comment out:
```hcl
ccoe_boundary = ""
```

### Issue: KMS key doesn't exist

See [How to Create KMS Key](#how-to-create-kms-key) above.

### Issue: Disconnected/Air-gapped install

1. Mirror images to internal registry
2. Change `release_image`:
```hcl
release_image = "your-registry.internal/ocp-release:4.16.9-x86_64"
```
3. Merge internal registry creds into pull secret

---

## Next Steps

After filling tfvars:

1. ✅ Verify all values are correct
2. ✅ Ensure KMS key exists and vmimport has access
3. ✅ Ensure pull secret is in place
4. ✅ Ensure custom installer is built: `./openshift-install version`
5. ✅ Run: `terraform init`
6. ✅ Run: `terraform plan -var-file="env/my-cluster.tfvars"`
7. ✅ Run: `terraform apply -var-file="env/my-cluster.tfvars"`

**Deployment time**: ~45-60 minutes

---

**Questions?** Check the main `README.md` or `QUICKSTART.md`
