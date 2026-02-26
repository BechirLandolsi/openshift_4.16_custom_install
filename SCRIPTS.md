# Shell Scripts Reference

Quick reference for all shell scripts in this delivery.

---

## Custom AMI Build Scripts

Located in `custom-ami-build/`

### create-kms-key.sh

Creates a KMS key for EBS encryption.

```bash
# Basic usage (uses defaults)
./create-kms-key.sh

# With custom settings
export AWS_REGION="eu-west-1"
export KMS_KEY_ALIAS="alias/my-openshift-key"
./create-kms-key.sh
```

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | From AWS CLI config | AWS region |
| `KMS_KEY_ALIAS` | `alias/openshift-ebs-encryption` | Key alias name |
| `KMS_KEY_DESCRIPTION` | `OpenShift 4.16 EBS Encryption Key` | Key description |

**Output:** Creates `kms-key-result.env` with key details.

---

### create-custom-ami.sh

Creates a KMS-encrypted RHCOS AMI.

```bash
# After creating KMS key
source kms-key-result.env
./create-custom-ami.sh

# Or with manual settings
export AWS_REGION="eu-west-3"
export KMS_KEY_ID="arn:aws:kms:eu-west-3:123456789012:key/..."
export RHCOS_VERSION="4.16.51"
./create-custom-ami.sh
```

**Environment Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | From AWS CLI config | AWS region |
| `KMS_KEY_ID` | (from kms-key-result.env) | KMS key ARN or alias |
| `RHCOS_VERSION` | `4.16.51` | RHCOS version to download |
| `S3_BUCKET_NAME` | auto-generated | Temp bucket for VMDK upload |

**Output:** Creates `custom-ami-result.env` with AMI ID.

---

### example-usage.sh

Shows the complete AMI creation workflow.

```bash
# View the example
cat example-usage.sh

# Run as reference
./example-usage.sh
```

---

## Terraform Scripts

Located in `terraform-openshift-v18/`

### Pre-Install Check

#### pre-install-checks.sh

**Pre-installation conflict detection (READ-ONLY).** Run before `terraform apply` to detect resources that would cause "already exists" errors.

```bash
# Auto-detect tfvars file
./pre-install-checks.sh

# Specify tfvars file
./pre-install-checks.sh env/demo.tfvars
./pre-install-checks.sh env/prod.tfvars
```

**What it checks:**
| Resource | Error it prevents |
|----------|-------------------|
| DNS records (`*.apps.cluster.domain`) | `InvalidChangeBatch` |
| S3 bucket (`cluster-infra-terraform-state-storage-s3`) | `BucketAlreadyOwnedByYou` |
| DynamoDB table (`cluster-terraform-locks`) | `ResourceInUseException` |
| KMS alias (`alias/s3-terraform-state-cluster`) | `AlreadyExistsException` |
| Local files (`installer-files/`, `terraform.tfstate`) | State conflicts |

**Output:**
- Lists all conflicts found
- Provides exact commands to delete each conflict
- Does NOT delete anything automatically

---

### Core Lifecycle Scripts

#### create-cluster.sh

Called by Terraform to run the OpenShift installer. **Do not run manually.**

```bash
# Called automatically by Terraform with:
# - IgnoreErrorsOnSharedTags=On
# - ForceOpenshiftInfraIDRandomPart=${infra_random_id}
# - Starts background DNS creation process
```

**What it does:**
1. Loads configuration from tfvars file
2. Sets environment variables for custom installer
3. Starts `create-private-dns.sh` in background
4. Runs `openshift-install create cluster`

---

#### create-private-dns.sh

Background script that creates DNS records during installation. **Do not run manually.**

```bash
# Called by create-cluster.sh with:
./create-private-dns.sh <cluster_name> <domain> <region> [public_zone_id]
```

**What it does:**
1. Waits for private hosted zone to be created by installer
2. Waits for ingress LoadBalancer to be ready
3. Creates `*.apps` CNAME record in private zone
4. Creates `*.apps` CNAME record in public zone
5. Logs progress to `output/private-dns.log`

**Why it's needed:** Solves the authentication operator deadlock where the installer waits for auth operator, but auth operator needs DNS to resolve `oauth-openshift.apps.*`.

---

#### clean-cluster.sh

Orchestrates cleanup during `terraform destroy`. **Do not run manually.**

```bash
# Called by Terraform during destroy with:
# - hosted_zone, cluster_name, domain, bucket, tfvars_file
```

**What it does:**
1. Fetches installer files from S3 if not local
2. Calls `destroy-cluster.sh --auto-approve`
3. Preserves local files

---

#### save-cluster-states.sh

Backs up cluster state to S3. **Called automatically by Terraform.**

---

### Destroy Scripts

#### destroy-cluster.sh

**Comprehensive cluster destroy script.** Safely deletes ALL cluster resources using tags and naming patterns.

```bash
# Dry-run mode (shows what would be deleted)
./destroy-cluster.sh --dry-run

# Interactive mode (asks for confirmation)
./destroy-cluster.sh

# Non-interactive mode
./destroy-cluster.sh --auto-approve

# Specify tfvars file
./destroy-cluster.sh --var-file=env/prod.tfvars
./destroy-cluster.sh env/prod.tfvars
```

**Options:**
| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be deleted without deleting |
| `--auto-approve` | Non-interactive, no confirmation |
| `--var-file=<file>` | Specify tfvars file |
| `<file>.tfvars` | Specify tfvars file (shorthand) |

**What it deletes (12 phases):**
1. OpenShift cluster (via `openshift-install destroy cluster`)
2. EC2 instances (by cluster tag/name)
3. Elastic Network Interfaces
4. Load balancers (NLB/ALB/Classic)
5. Target groups
6. Security groups
7. Route53 DNS records (public & private zones)
8. IAM roles (OIDC + Terraform-created)
9. IAM policies
10. OIDC provider
11. S3 buckets (OIDC + state)
12. DynamoDB table

**Safety:**
- Only deletes resources with cluster tag `kubernetes.io/cluster/<infra-id>=owned`
- Only deletes resources named with cluster name prefix
- Preserves local files (`installer-files/`, `output/`, `terraform.tfstate`)
- Uses `SkipDestroyingSharedTags=On` to protect shared subnet tags

---

#### destroy-cluster2.sh

**Targeted destroy script (customer version).** Deletes ONLY specific hardcoded resources.

```bash
# Dry-run mode
./destroy-cluster2.sh --dry-run

# Interactive mode
./destroy-cluster2.sh

# Non-interactive mode
./destroy-cluster2.sh --auto-approve
```

**What it deletes (hardcoded list):**
- DNS records: `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`
- OIDC IAM roles (6 roles):
  - `<cluster>-openshift-cloud-credential-operator-cloud-credential-operat`
  - `<cluster>-openshift-cloud-network-config-controller-cloud-credentials`
  - `<cluster>-openshift-cluster-csi-drivers-ebs-cloud-credentials`
  - `<cluster>-openshift-image-registry-installer-cloud-credentials`
  - `<cluster>-openshift-ingress-operator-cloud-credentials`
  - `<cluster>-openshift-machine-api-aws-cloud-credentials`
- Terraform IAM roles: `ocp-controlplane-role`, `ocp-worker-role`
- Terraform IAM policies: `ocp-controlplane-policy`, `ocp-worker-policy`

**Use case:** When you need precise control over which resources are deleted.

---

### Verification Script

#### verify-cluster.sh

Verifies cluster health, security settings, and encryption.

```bash
# Auto-detect tfvars file
./verify-cluster.sh

# Specify tfvars file
./verify-cluster.sh env/demo.tfvars
./verify-cluster.sh env/prod.tfvars
```

**What it checks:**
| Check | Description |
|-------|-------------|
| Cluster Nodes | All nodes Ready status |
| Cluster Operators | All operators Available/not Degraded |
| EC2 Instances | Instances with cluster tag |
| IMDSv2 Enforcement | All nodes have `HttpTokens=required` |
| KMS Encryption | All EBS volumes encrypted with KMS |
| AMI Encryption | AMI encrypted with correct KMS key |
| KMS Key Policy | Correct principals in key policy |

**Output:** Color-coded summary with pass/fail status for each check.

---

### Utility Scripts

#### wait.sh

Polling utility used by Terraform. **Do not run manually.**

#### get-ingress-lb.sh

Retrieves ingress load balancer ARN. **Called automatically by Terraform.**

**Behavior:**
- Returns LoadBalancer ARN when cluster exists
- Returns dummy ARN when kubeconfig missing (for destroy)
- Supports both NLB and classic ELB

---

## Customer Tags Simulation Scripts

Located in `terraform-openshift-v18/customer-tags-simulation/`

These scripts simulate an environment with immutable subnet tags.

```bash
# 1. Tag subnets
./manual-tag-subnets.sh ../env/demo.tfvars

# 2. Verify tags
./verify-manual-tags.sh ../env/demo.tfvars

# 3. Lock tags (make immutable)
./lock-subnet-tags.sh ../env/demo.tfvars

# 4. Run Terraform (from parent directory)
cd .. && terraform apply -var-file=env/demo.tfvars

# 5. Unlock tags
cd customer-tags-simulation
./unlock-subnet-tags.sh ../env/demo.tfvars

# 6. Monitor for tag errors
./monitor-tag-errors.sh ../env/demo.tfvars

# 7. Cleanup
./cleanup-manual-tags.sh ../env/demo.tfvars
```

| Script | Purpose |
|--------|---------|
| `manual-tag-subnets.sh` | Tags subnets with OpenShift tags |
| `verify-manual-tags.sh` | Verifies tags are applied |
| `lock-subnet-tags.sh` | Creates IAM deny policy (immutable) |
| `unlock-subnet-tags.sh` | Removes IAM deny policy |
| `monitor-tag-errors.sh` | Watches CloudTrail for errors |
| `cleanup-manual-tags.sh` | Removes all tags and restrictions |

---

## Quick Reference

### Fresh Install Workflow

```bash
# 1. Create KMS key and AMI
cd custom-ami-build/
./create-kms-key.sh
source kms-key-result.env
./create-custom-ami.sh
source custom-ami-result.env

# 2. Configure Terraform
cd ../terraform-openshift-v18/
cp env/demo.tfvars env/my-cluster.tfvars
vi env/my-cluster.tfvars  # Update with your values

# 3. Pre-install check
./pre-install-checks.sh env/my-cluster.tfvars
# Fix any conflicts listed

# 4. Deploy
terraform init
terraform apply -var-file=env/my-cluster.tfvars

# 5. Verify
./verify-cluster.sh env/my-cluster.tfvars
```

### Reinstall Workflow

```bash
cd terraform-openshift-v18/

# 1. Destroy existing cluster
terraform destroy -var-file=env/my-cluster.tfvars

# 2. Check for remaining resources
./pre-install-checks.sh env/my-cluster.tfvars
# Clean up any conflicts manually

# 3. Reinstall
terraform init
terraform apply -var-file=env/my-cluster.tfvars
```

### Manual Destroy Workflow

```bash
cd terraform-openshift-v18/

# 1. Dry-run first
./destroy-cluster.sh --dry-run

# 2. Review what will be deleted

# 3. Execute destroy
./destroy-cluster.sh --auto-approve

# 4. Verify cleanup
./pre-install-checks.sh env/my-cluster.tfvars
```

### Troubleshooting

```bash
# Check cluster health
./verify-cluster.sh env/demo.tfvars

# Check for resource conflicts
./pre-install-checks.sh env/demo.tfvars

# If terraform destroy fails, use manual destroy
./destroy-cluster.sh --auto-approve

# Check DNS creation logs
cat output/private-dns.log

# Check installer logs
tail -f output/openshift-install.log
```

---

**Last Updated:** January 30, 2026
