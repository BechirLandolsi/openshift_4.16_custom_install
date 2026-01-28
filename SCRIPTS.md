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
| `AWS_REGION` | `eu-west-3` | AWS region |
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
| `AWS_REGION` | `eu-west-3` | AWS region |
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

### Core Lifecycle Scripts

#### create-cluster.sh

Called by Terraform to run the OpenShift installer. **Do not run manually.**

```bash
# Called automatically by Terraform with:
# - IgnoreErrorsOnSharedTags=On
# - ForceOpenshiftInfraIDRandomPart=${infra_random_id}
```

#### delete-cluster.sh

Destroys the OpenShift cluster. **Do not run manually.**

```bash
# Called automatically by Terraform with:
# - SkipDestroyingSharedTags=On
```

#### clean-cluster.sh

Orchestrates cleanup during `terraform destroy`. **Do not run manually.**

#### save-cluster-states.sh

Backs up cluster state to S3. **Called automatically by Terraform.**

---

### Cleanup Scripts

#### destroy-cluster.sh

**Comprehensive cluster destroy script.** Safely deletes ALL cluster resources using tags and naming patterns.

```bash
# Interactive mode (asks for confirmation)
./destroy-cluster.sh

# Non-interactive mode
./destroy-cluster.sh --auto-approve

# Dry-run mode (shows what would be deleted)
./destroy-cluster.sh --dry-run
```

**Options:**
| Option | Description |
|--------|-------------|
| (none) | Interactive mode, asks for confirmation |
| `--auto-approve` | Non-interactive, no confirmation |
| `--dry-run` | Show what would be deleted without deleting |

**What it deletes (in order):**
1. OpenShift cluster (via installer)
2. EC2 instances (by cluster tag)
3. Load balancers (NLB/ALB/Classic)
4. Target groups
5. Security groups (by cluster tag)
6. Route53 DNS records (public & private zones)
7. IAM roles (OIDC + Terraform-created)
8. IAM policies
9. OIDC provider
10. S3 buckets (OIDC + state)
11. DynamoDB table
12. KMS aliases (not keys)
13. Local files

**Safety:** Only deletes resources with cluster tag `kubernetes.io/cluster/<infra-id>=owned` or named with cluster name prefix.

---

#### full-cleanup.sh

**Recommended cleanup script.** Removes all local files and optionally AWS resources.

```bash
# Local files only (safe)
./full-cleanup.sh

# Full cleanup including AWS resources (uses destroy-cluster.sh)
./full-cleanup.sh --with-aws-destroy
```

**Options:**
| Option | Description |
|--------|-------------|
| (none) | Remove local files only |
| `--with-aws-destroy` | Also destroy AWS resources (calls destroy-cluster.sh) |

**What it removes:**
- Terraform state and cache
- OpenShift installer files
- CCOCTL output
- Log files
- (Optional) All AWS cluster resources

---

#### manual-cleanup.sh

Manual cleanup when `terraform destroy` fails.

```bash
# Edit variables in script first!
vi manual-cleanup.sh  # Set REGION, CLUSTER_NAME, ACCOUNT_ID

# Then run
./manual-cleanup.sh
```

**Note:** Edit the script variables before running:
- `REGION` - AWS region
- `CLUSTER_NAME` - Your cluster name
- `ACCOUNT_ID` - Your AWS account ID

---

#### force-delete-iam.sh

Force deletes IAM resources causing `EntityAlreadyExists` errors.

```bash
# Edit variables in script first!
vi force-delete-iam.sh

# Then run
./force-delete-iam.sh
```

**Note:** Script has hardcoded role/policy names. Edit before use.

---

#### delete-roles.sh

Deletes ccoctl-created IAM roles matching a prefix.

```bash
./delete-roles.sh <cluster-name>

# Example
./delete-roles.sh my-ocp-cluster
```

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<prefix>` | Cluster name prefix to match roles |

---

#### delete-record.sh

Deletes a Route53 DNS record.

```bash
./delete-record.sh <hosted-zone-id> <record-name>

# Example
./delete-record.sh Z0123456789 api.my-cluster.example.com
```

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<hosted-zone-id>` | Route53 hosted zone ID |
| `<record-name>` | Full DNS record name to delete |

---

### Verification Script

#### verify-cluster.sh

Verifies cluster health, KMS encryption, and tagging.

```bash
./verify-cluster.sh
```

**Auto-detects from `env/demo.tfvars`:**
- Cluster name
- Infra ID
- Region
- KMS alias

**What it checks:**
1. Node status (all Ready)
2. Cluster operators (all healthy)
3. EC2 instances with cluster tag
4. KMS encryption on EBS volumes
5. AMI encryption status
6. KMS key policy principals

---

### Utility Scripts

#### wait.sh

Polling utility used by Terraform. **Do not run manually.**

#### get-ingress-lb.sh

Retrieves ingress load balancer DNS. **Called automatically by Terraform.**

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

# 2. Update tfvars with AMI ID
cd ../terraform-openshift-v18/
vi env/demo.tfvars

# 3. Deploy
terraform init
terraform apply -var-file=env/demo.tfvars

# 4. Verify
./verify-cluster.sh
```

### Reinstall Workflow

```bash
cd terraform-openshift-v18/

# Clean everything
./full-cleanup.sh --with-aws-destroy

# Reinstall
terraform init
terraform apply -var-file=env/demo.tfvars
```

### Troubleshooting

```bash
# Check cluster health
./verify-cluster.sh

# If terraform destroy fails
./manual-cleanup.sh

# If IAM resources stuck
./force-delete-iam.sh

# If roles exist from previous install
./delete-roles.sh my-ocp-cluster
```

---

**Last Updated:** January 26, 2026
