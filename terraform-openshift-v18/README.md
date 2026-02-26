# Terraform OpenShift 4.16 Deployment Module

This Terraform module automates the deployment of OpenShift 4.16 on AWS using a custom installer with manual credentials mode (STS/OIDC).

**Version**: v18 (for OpenShift 4.16)  
**Parent Documentation**: See `../README.md` for complete installation guide

---

## Overview

This Terraform module provisions:
- **S3 bucket** for OIDC provider configuration
- **IAM OIDC identity provider** for cluster authentication
- **IAM roles** for control plane and workers (via `ccoctl`)
- **SSH key pair** for cluster node access
- **OpenShift cluster** using custom installer
- **Route53 DNS records** for ingress (*.apps domain)

**Deployment Mode**: Manual credentials with AWS STS (Security Token Service) and OIDC provider

---

## Prerequisites

### Before Using This Module

Complete these steps from the main README.md first:

1. ✅ **Custom AMI Created** - RHCOS 4.16 AMI with KMS encryption (see `../custom-ami-build/`)
2. ✅ **Custom Installer Built** - Modified OpenShift installer binary in this directory (see `../README.md` Part 2)
3. ✅ **AWS Prerequisites Met** - VPC, subnets, Route53 hosted zone, NAT Gateway, etc.
4. ✅ **Red Hat Pull Secret** - Obtained from console.redhat.com and placed in `openshift/openshift_pull_secret.json`

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **Terraform** | 1.5.0+ | https://www.terraform.io/downloads |
| **AWS CLI** | 2.x | https://aws.amazon.com/cli/ |
| **ccoctl** | 4.16.x | See installation instructions below |
| **Custom openshift-install** | 4.16.x | Built in Part 2 of main guide |

### Install ccoctl (REQUIRED)

The `ccoctl` tool is **mandatory** for creating IAM roles with manual credentials mode.

#### Download and Install

```bash
# Set variables
CCOCTL_VERSION="4.16.9"
ARCH="amd64"  # or arm64
OS="linux"     # or darwin for macOS

# Download ccoctl
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${CCOCTL_VERSION}/ccoctl-${OS}-${ARCH}.tar.gz

# Extract
tar xzf ccoctl-${OS}-${ARCH}.tar.gz

# Install to system path
sudo mv ccoctl /usr/local/bin/

# Make executable
sudo chmod +x /usr/local/bin/ccoctl

# Verify installation
ccoctl --help
```

**Note**: Replace version, architecture, and OS as needed for your bastion host.

### AWS Credentials

Configure AWS CLI with credentials:

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., eu-west-3)
# Enter output format (json)

# Verify
aws sts get-caller-identity
```

### IAM Permissions Required

Your AWS user/role needs permissions for:
- **IAM**: Create/delete OIDC providers, roles, policies
- **S3**: Create/delete buckets, upload/download objects
- **EC2**: Full access (launch instances, create security groups, etc.)
- **ELB**: Create/delete load balancers
- **Route53**: Create/delete DNS records in hosted zone
- **KMS**: Use specified KMS keys for encryption

See main README.md for complete IAM policy details.

---

## Quick Start

### 1. Configure Variables

Edit `env/demo.tfvars` with your environment-specific values:

```bash
cd env
vi demo.tfvars

# Key variables to configure:
# - account_id: Your AWS account ID
# - region: AWS region (e.g., eu-west-3)
# - vpc_id: Existing VPC ID
# - subnet_ids: Map of private subnet IDs
# - domain: Base DNS domain
# - hosted_zone: Route53 hosted zone ID
# - kms_ec2_alias: KMS key alias for EBS encryption
# - openshift_ssh_key: SSH public key for node access
```

See `env/VARIABLES-EXPLAINED.md` for detailed explanation of all variables.

### 2. Place Custom Installer

Ensure the custom OpenShift installer binary is in this directory:

```bash
# Check if installer exists
ls -l ./openshift-install

# Verify it's the custom build
./openshift-install version
```

### 3. Initialize Terraform

```bash
terraform init
```

This will:
- Download required providers (AWS)
- Initialize backend (local state by default)
- Prepare working directory

### 4. Review Plan

```bash
terraform plan -var-file="env/demo.tfvars"
```

Review the resources that will be created.

### 5. Deploy Cluster

```bash
# Set environment variables for custom installer behavior
export IgnoreErrorsOnSharedTags=On
export SkipDestroyingSharedTags=On
export ForceOpenshiftInfraIDRandomPart=<your-infra-id-suffix>  # e.g., d44a5

# Apply Terraform
terraform apply -var-file="env/demo.tfvars"

# Type 'yes' when prompted
```

**Deployment Time**: Approximately 40-60 minutes

### 6. Access Cluster

After successful deployment:

```bash
# Kubeconfig location
export KUBECONFIG=$(pwd)/installer-files/auth/kubeconfig

# Get admin password
cat installer-files/auth/kubeadmin-password

# Check cluster
oc get nodes
oc get co  # Check cluster operators
```

---

## Configuration Files

### Core Files

- **env/demo.tfvars** - Variable definitions (customize for your environment)
- **env/VARIABLES-EXPLAINED.md** - Detailed variable documentation
- **openshift/openshift_pull_secret.json** - Red Hat pull secret (required)

### Terraform Configuration

- **variables.tf** - Variable declarations
- **providers.tf** - AWS provider configuration
- **backend.tf.disabled** - Optional S3 remote state backend

### Resource Definitions

- **main.tf** - Core resources (SSH keys)
- **main.openshift.tf** - OIDC and IAM role creation
- **iam.tf** - Control plane and worker IAM resources
- **s3.tf** - OIDC S3 bucket
- **templates.tf** - install-config.yaml and manifest templates
- **openshift.prepare.tf** - Manifest preparation
- **openshift.install.tf** - Cluster installation execution
- **openshift.day2.tf** - Post-installation configuration
- **output.tf** - Terraform outputs

### Scripts

- **create-cluster.sh** - Wrapper for installer create cluster
- **delete-cluster.sh** - Wrapper for installer destroy cluster
- **clean-cluster.sh** - Cleanup orchestration (called by terraform destroy)
- **save-cluster-states.sh** - Backup installer files to S3
- **delete-roles.sh** - IAM role cleanup
- **delete-record.sh** - Route53 record deletion
- **get-ingress-lb.sh** - Retrieve ingress load balancer info
- **wait.sh** - Polling utility for resource readiness

---

## Cluster Destruction

### Normal Destroy

```bash
# Ensure environment variables are set
export SkipDestroyingSharedTags=On
export IgnoreErrorsOnSharedTags=On

# Run destroy
terraform destroy -var-file="env/demo.tfvars"

# Type 'yes' when prompted
```

**Destroy Time**: Approximately 10-25 minutes

### What Gets Deleted

1. **By Terraform Destroy**:
   - S3 bucket (OIDC)
   - IAM OIDC provider
   - IAM roles and policies
   - DNS records (api, api-int)

2. **By openshift-install destroy**:
   - EC2 instances (control plane, workers, bootstrap)
   - Load balancers
   - Security groups
   - Volumes
   - Network interfaces
   - S3 buckets created by installer

### Manual Cleanup (if destroy fails)

If Terraform destroy fails, you can manually run:

```bash
# Delete cluster using installer
export SkipDestroyingSharedTags=On
export IgnoreErrorsOnSharedTags=On
./openshift-install destroy cluster --dir=installer-files --log-level=debug

# Delete IAM roles
sh delete-roles.sh <cluster-name>

# Delete DNS records
sh delete-record.sh <hosted-zone-id> api.<cluster>.<domain>
sh delete-record.sh <hosted-zone-id> api-int.<cluster>.<domain>
```

---

## Troubleshooting

### Common Issues

#### 1. `ccoctl: command not found`

**Solution**: Install ccoctl as described in Prerequisites section above.

#### 2. `flag needs an argument: --permissions-boundary-arn`

**Cause**: `ccoe_boundary` variable is empty but being passed to ccoctl.

**Solution**: Either:
- Set `ccoe_boundary = ""` in demo.tfvars (if no boundary needed)
- Or provide actual permission boundary ARN

#### 3. `networkType OpenShiftSDN is not supported`

**Cause**: OpenShift 4.16 requires OVNKubernetes.

**Solution**: This is already fixed in templates.tf. Delete old installer-files and re-run.

#### 4. `hosted zone is not associated with the VPC`

**Cause**: Using Internal publish mode with public hosted zone.

**Solution**: Either:
- Use `publish: External` in templates.tf
- Or create private hosted zone and associate with VPC

#### 5. Bootstrap fails with "i/o timeout" reaching quay.io

**Cause**: No internet access from private subnets (missing NAT Gateway).

**Solution**: Ensure NAT Gateway exists and route tables have `0.0.0.0/0` → NAT Gateway.

### Debug Mode

Run with debug logging:

```bash
export TF_LOG=DEBUG
terraform apply -var-file="env/demo.tfvars"
```

Check installer logs:

```bash
tail -f installer-files/.openshift_install.log
```

---

## Architecture

### Deployment Flow

```
1. Terraform creates S3 bucket for OIDC
2. ccoctl generates serviceaccount-signer keys
3. ccoctl creates OIDC configuration (dry-run)
4. Terraform uploads OIDC files to S3 bucket
5. Terraform creates IAM OIDC identity provider
6. ccoctl creates IAM roles (control plane, workers)
7. Terraform generates install-config.yaml
8. Terraform runs openshift-install create manifests
9. Terraform applies custom ingress configuration
10. Terraform runs openshift-install create cluster
11. Bootstrap node launches and provisions control plane
12. Control plane nodes become ready
13. Worker nodes join cluster
14. Bootstrap node terminates
15. Terraform creates *.apps DNS record pointing to ingress LB
```

### Resource Dependencies

```
aws_key_pair
  ↓
ccoctl create-key-pair
  ↓
ccoctl create-identity-provider (dry-run)
  ↓
S3 bucket + OIDC files upload
  ↓
IAM OIDC provider
  ↓
ccoctl create-iam-roles
  ↓
install-config.yaml generation
  ↓
openshift-install create manifests
  ↓
openshift-install create cluster
  ↓
Ingress DNS record
```

---

## Outputs

After successful deployment, Terraform displays:

- **cluster_name**: Name of the OpenShift cluster
- **cluster_id**: InfraID used for tagging
- **api_url**: API server URL
- **console_url**: Web console URL
- **kubeconfig_path**: Path to kubeconfig file
- **kubeadmin_password_path**: Path to admin password
- **oidc_provider_arn**: ARN of IAM OIDC provider
- **control_plane_role_arn**: ARN of control plane IAM role
- **worker_role_arn**: ARN of worker IAM role

---

## Version History

**v18** (OpenShift 4.16)
- Updated for OpenShift 4.16.x
- Changed networkType to OVNKubernetes
- Enhanced destroy logic with S3 fallback
- Improved error handling in cleanup scripts
- Fixed line ending issues (CRLF → LF)

**v17** (OpenShift 4.14)
- Added metadata.json backup to S3
- Improved state recovery from S3

---

## Support

For issues or questions:
1. Check main README.md troubleshooting section
2. Review OpenShift installer logs in `installer-files/.openshift_install.log`
3. Check Terraform debug logs with `TF_LOG=DEBUG`
4. Refer to Red Hat OpenShift 4.16 documentation

---

**Important**: This module is designed for AWS deployments with existing VPC infrastructure and manual credentials mode (STS). It requires the custom OpenShift installer with tag bypass modifications.
