# OpenShift 4.16 AWS Installation - File Index

## Quick Navigation

| I want to... | Go to... |
|--------------|----------|
| 🚀 **Deploy quickly** | [QUICKSTART.md](QUICKSTART.md) |
| 📖 **Understand everything** | [README.md](README.md) |
| 📋 **See what's included** | This file (INDEX.md) |
| 📝 **Summary for management** | [SUMMARY.md](SUMMARY.md) |
| 🖼️ **Build custom AMI** | [custom-ami-build/README.md](custom-ami-build/README.md) |
| 🔧 **Build custom installer** | [openshift-installer-modifications.4.16/README.md](openshift-installer-modifications.4.16/README.md) |

---

## Complete File Structure

### 📁 Root Directory Files

```
Openshift_4.16/
│
├── README.md                    # 📘 MAIN DOCUMENTATION - START HERE
│                                  - Part 1: Custom AMI Creation
│                                  - Part 2: Building Custom OpenShift Installer
│                                  - Part 3: Terraform Configuration
│                                  - Part 4: Step-by-Step Installation
│                                  - Part 5: Disconnected Installation
│                                  - Troubleshooting Guide
│                                  - Appendices and References
│
├── QUICKSTART.md                # ⚡ FAST-TRACK GUIDE (~2 hours to cluster)
│                                  - Prerequisites checklist
│                                  - 5 phases with timelines
│                                  - Quick troubleshooting
│                                  - Critical values reference
│
├── SUMMARY.md                   # 📋 EXECUTIVE SUMMARY
│                                  - Customer requirements
│                                  - What was delivered
│                                  - Key features
│                                  - Timeline estimates
│
└── INDEX.md                     # 📑 THIS FILE - Navigation guide
```

---

### 📁 custom-ami-build/

**Purpose**: Create custom RHCOS AMI with IMDSv2 and KMS encryption

```
custom-ami-build/
│
├── create-custom-ami.sh               # 🔨 Automated AMI creation script
│                                        - Downloads RHCOS VMDK
│                                        - Imports with KMS encryption
│                                        - Registers custom AMI
│                                        - Red Hat official method
│                                        - ~30-40 minute process
│
├── custom-ami-result.env              # 📝 Generated AMI details (after build)
│                                        - AMI ID
│                                        - Snapshot ID
│                                        - Region and version info
│
└── README.md                          # 📖 AMI Build Documentation
                                         - Prerequisites
                                         - Build steps (automated & manual)
                                         - Verification procedures
                                         - IMDSv2 configuration explanation
                                         - Troubleshooting
```

**Key Files**:
- `create-custom-ami.sh`: Automated AMI creation script
- `custom-ami-result.env`: Generated file with AMI details
- `README.md`: Complete AMI build guide

**Usage**:
```bash
cd custom-ami-build/
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh
source custom-ami-result.env
```

---

### 📁 openshift-installer-modifications.4.16/

**Purpose**: Modified OpenShift installer source files that bypass subnet tagging

```
openshift-installer-modifications.4.16/
│
├── README.md                                  # 📖 Build Instructions
│                                                - What was modified
│                                                - Why modifications are needed
│                                                - Build steps
│                                                - Environment variables usage
│
└── pkg/
    ├── asset/
    │   ├── cluster/aws/
    │   │   └── aws.go                         # ✅ MODIFIED: Skip subnet tagging errors
    │   │                                        - Added: IgnoreErrorsOnSharedTags env var
    │   │                                        - Lines modified: 81-84
    │   │
    │   ├── installconfig/
    │   │   └── clusterid.go                   # ✅ MODIFIED: Control InfraID generation
    │   │                                        - Added: ForceOpenshiftInfraIDRandomPart env var
    │   │                                        - Lines modified: 79-82
    │   │
    │   └── releaseimage/
    │       └── default.go                     # ✅ MODIFIED: Pin to OpenShift 4.16.9
    │                                            - Updated default release image
    │                                            - Line modified: 24
    │
    └── destroy/aws/
        └── shared.go                          # ✅ MODIFIED: Skip tag cleanup on destroy
                                                 - Added: SkipDestroyingSharedTags env var
                                                 - Lines modified: 56-59, 118-124
```

**Environment Variables Introduced**:

| Variable | File | Purpose |
|----------|------|---------|
| `IgnoreErrorsOnSharedTags` | aws.go, shared.go | Skip tagging permission errors |
| `ForceOpenshiftInfraIDRandomPart` | clusterid.go | Set custom InfraID suffix |
| `SkipDestroyingSharedTags` | shared.go | Skip tag removal on delete |

**How to Build**:
```bash
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer
# Copy modified files from this directory
./hack/build.sh
```

**Total Modifications**: 
- Files changed: 4
- Lines modified: ~23
- Build time: ~10 minutes

---

### 📁 terraform-openshift-v18/

**Purpose**: Infrastructure as Code for OpenShift 4.16 deployment

```
terraform-openshift-v18/
│
├── Core Terraform Files
│   ├── providers.tf              # AWS provider configuration
│   ├── backend.tf                # S3 backend for state
│   ├── variables.tf              # Input variables definitions
│   ├── main.tf                   # Main infrastructure resources
│   ├── output.tf                 # Output values
│   ├── templates.tf              # install-config.yaml templates
│   │
│   ├── iam.tf                    # IAM roles and policies
│   ├── ssh_key.tf                # SSH key generation
│   ├── s3.tf                     # S3 buckets for OIDC
│   ├── s3.dynamo.tf              # DynamoDB for state locking
│   │
│   ├── main.openshift.tf         # OpenShift orchestration
│   ├── openshift.prepare.tf      # Manifest generation
│   ├── openshift.install.tf      # Cluster installation
│   └── openshift.day2.tf         # Post-install configuration
│
├── Installation Scripts
│   ├── create-cluster.sh         # 🚀 Cluster creation wrapper
│   │                               - Sets IgnoreErrorsOnSharedTags=On
│   │                               - Sets ForceOpenshiftInfraIDRandomPart
│   │                               - Runs openshift-install create
│   │
│   ├── delete-cluster.sh         # 🗑️ Cluster deletion wrapper
│   │                               - Sets SkipDestroyingSharedTags=On
│   │                               - Runs openshift-install destroy
│   │
│   ├── clean-cluster.sh          # 🧹 Cleanup script
│   ├── get-ingress-lb.sh         # 🔍 Extract ingress LB details
│   ├── save-cluster-states.sh    # 💾 Save artifacts to S3
│   ├── wait.sh                   # ⏱️ Wait for conditions
│   │
│   ├── delete-record.sh          # Delete DNS records
│   ├── delete-role.sh            # Delete single IAM role
│   ├── delete-roles.sh           # Delete all IAM roles
│   ├── test-roles.sh             # Test IAM role permissions
│   └── env.sh                    # Environment setup
│
├── env/                          # 📂 Environment Configurations
│   └── ocp-skw-hprod-plaasma-bkprestore-d44a5.tfvars
│                                   - Example from 4.14
│                                   - Copy and modify for your cluster
│
├── openshift/                    # 📂 OpenShift Assets
│   └── openshift_pull_secret.json  - Red Hat pull secret
│                                     - Download from console.redhat.com
│
├── installer-files/              # 📂 Generated during installation
│   ├── auth/
│   │   ├── kubeconfig            - Cluster access credentials
│   │   └── kubeadmin-password    - Initial admin password
│   ├── metadata.json             - Cluster metadata
│   └── .openshift_install_state.json - Installation state
│
└── output/                       # 📂 Installation artifacts
    └── openshift-install.log     - Installation logs
```

**Key Configuration Files**:

1. **variables.tf** (281 lines)
   - All input variable definitions
   - Default values and descriptions
   - Network, compute, storage configurations

2. **env/your-cluster.tfvars**
   - Cluster-specific values
   - AWS account details
   - Network configuration
   - Instance types and sizing

3. **create-cluster.sh**
   ```bash
   export IgnoreErrorsOnSharedTags=On
   export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"
   ./openshift-install create cluster --dir=installer-files --log-level=debug
   ```

4. **delete-cluster.sh**
   ```bash
   export SkipDestroyingSharedTags=On
   ./openshift-install destroy cluster --dir=installer-files --log-level=debug
   ```

**Deployment Workflow**:
```
terraform init
     ↓
terraform plan -var-file="env/your-cluster.tfvars"
     ↓
terraform apply
     ↓
  (Automatic)
     ↓
create-cluster.sh runs
     ↓
Cluster deploys (~45 min)
     ↓
Cluster ready ✅
```

---

## Documentation Map

### 🎯 Start Here Based on Your Role

#### Platform Engineer / DevOps
**Goal**: Deploy cluster quickly
1. ✅ [QUICKSTART.md](QUICKSTART.md) - Follow 5 phases
2. ✅ [custom-ami-build/README.md](custom-ami-build/README.md) - Build AMI
3. ✅ [openshift-installer-modifications.4.16/README.md](openshift-installer-modifications.4.16/README.md) - Build installer

#### Solution Architect
**Goal**: Understand architecture and decisions
1. ✅ [SUMMARY.md](SUMMARY.md) - High-level overview
2. ✅ [README.md](README.md) - Complete documentation
3. ✅ Architecture Overview section

#### Manager / Project Lead
**Goal**: Timeline, resources, risks
1. ✅ [SUMMARY.md](SUMMARY.md) - Executive summary
2. ✅ Timeline section
3. ✅ Success criteria

#### Operations / Support
**Goal**: Maintain and troubleshoot
1. ✅ [README.md](README.md) - Part 4 (Installation)
2. ✅ Troubleshooting section
3. ✅ Day 2 operations

---

## File Statistics

### Documentation
- **README.md**: ~15,000 lines (comprehensive guide)
- **QUICKSTART.md**: ~400 lines (fast-track)
- **SUMMARY.md**: ~600 lines (executive overview)
- **Component READMEs**: ~300-500 lines each

### Code
- **Shell Script**: ~200 lines (AMI build - Red Hat official)
- **Go Modifications**: 4 files, ~23 lines total
- **Terraform Files**: ~30 files (infrastructure)

### Total Package
- **Files**: ~50+
- **Documentation**: ~16,000 lines
- **Code**: ~500 lines modified/added

---

## Usage Patterns

### Pattern 1: First-Time Deployment

```bash
# 1. Read documentation
less README.md         # or QUICKSTART.md for fast track

# 2. Build AMI
cd custom-ami-build/
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh

# 3. Build Installer
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer
# Copy files from openshift-installer-modifications.4.16/
./hack/build.sh

# 4. Configure Terraform
cd ../terraform-openshift-v18/
cp env/example.tfvars env/my-cluster.tfvars
# Edit env/my-cluster.tfvars

# 5. Deploy
terraform init
terraform plan -var-file="env/my-cluster.tfvars"
terraform apply
```

### Pattern 2: Troubleshooting

```bash
# Check main README troubleshooting section
less README.md          # Search for "Troubleshooting"

# Check installation logs
tail -f terraform-openshift-v18/output/openshift-install.log

# Verify configuration
cd terraform-openshift-v18/
terraform state list
```

### Pattern 3: Maintenance

```bash
# Update to 4.17 (future)
# 1. Build new AMI with RHCOS 4.17
cd custom-ami-build/
export RHCOS_VERSION="4.17.x"  # Update version
./create-custom-ami.sh

# 2. Build new installer
git clone https://github.com/openshift/installer.git -b release-4.17
# Reapply modifications
./hack/build.sh

# 3. Update Terraform
cd terraform-openshift-v18/
# Update release_image and ami in tfvars
terraform plan -var-file="env/my-cluster.tfvars"
```

---

## Key Concepts Reference

### Environment Variables

| Variable | Set In | Purpose | Example |
|----------|--------|---------|---------|
| `IgnoreErrorsOnSharedTags` | create-cluster.sh | Skip tagging errors | `On` |
| `SkipDestroyingSharedTags` | delete-cluster.sh | Skip tag cleanup | `On` |
| `ForceOpenshiftInfraIDRandomPart` | create-cluster.sh | Control InfraID | `abc12` |

### Custom AMI Components

| Component | Description |
|-----------|-------------|
| **KMS Encryption** | Customer-managed key for EBS volumes (baked into AMI) |
| **RHCOS Base** | Official Red Hat CoreOS for OpenShift 4.16 |
| **IMDSv2** | Configured at launch-time (NOT in AMI) - set in install-config.yaml |

### Terraform Resources

| Type | Count | Purpose |
|------|-------|---------|
| **IAM Roles** | ~10 | Control plane, worker, OIDC |
| **S3 Buckets** | ~3 | OIDC, state, cluster artifacts |
| **EC2 Instances** | 6+ | Masters (3) + Workers (3+) |
| **Load Balancers** | 2 | API + Ingress |
| **Route53 Records** | 2 | API + Wildcard ingress |

---

## Integration Points

### 1. AMI → Terraform
```hcl
# In env/your-cluster.tfvars
ami = "ami-0abcdef1234567890"  # From create-custom-ami.sh output
```

### 2. Installer → Terraform
```bash
# Terraform calls create-cluster.sh which runs:
./openshift-install create cluster --dir=installer-files
```

### 3. Environment Variables → Installer
```bash
# In create-cluster.sh
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"
```

---

## Verification Checklist

After setup, verify these files exist:

### Documentation
- [ ] README.md
- [ ] QUICKSTART.md
- [ ] SUMMARY.md
- [ ] INDEX.md (this file)

### AMI Build
- [ ] custom-ami-build/create-custom-ami.sh
- [ ] custom-ami-build/.gitignore
- [ ] custom-ami-build/README.md

### Installer Modifications
- [ ] openshift-installer-modifications.4.16/README.md
- [ ] openshift-installer-modifications.4.16/pkg/asset/cluster/aws/aws.go
- [ ] openshift-installer-modifications.4.16/pkg/asset/installconfig/clusterid.go
- [ ] openshift-installer-modifications.4.16/pkg/destroy/aws/shared.go
- [ ] openshift-installer-modifications.4.16/pkg/asset/releaseimage/default.go

### Terraform
- [ ] terraform-openshift-v18/*.tf (all terraform files)
- [ ] terraform-openshift-v18/*.sh (all scripts)
- [ ] terraform-openshift-v18/env/ (example tfvars)

---

## Quick Reference Cards

### AMI Build Commands
```bash
cd custom-ami-build/
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh
source custom-ami-result.env
```

### Installer Build Commands
```bash
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer
# Copy modified files
./hack/build.sh
```

### Terraform Commands
```bash
cd terraform-openshift-v18/
terraform init
terraform plan -var-file="env/my-cluster.tfvars" -out=tfplan
terraform apply tfplan
```

### Cluster Access
```bash
export KUBECONFIG=terraform-openshift-v18/installer-files/auth/kubeconfig
oc get nodes
oc get co
oc whoami --show-console
```

---

## External Resources

### Official Documentation
- [OpenShift 4.16 Docs](https://docs.openshift.com/container-platform/4.16/)
- [AWS Installation Guide](https://docs.openshift.com/container-platform/4.16/installing/installing_aws/)
- [Disconnected Installation](https://docs.openshift.com/container-platform/4.16/installing/disconnected_install/)

### Tools
- [Packer Documentation](https://www.packer.io/docs)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [OpenShift Installer GitHub](https://github.com/openshift/installer)

### Downloads
- [Red Hat Pull Secret](https://console.redhat.com/openshift/install/pull-secret)
- [RHCOS AMI List](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/)
- [OpenShift Client (oc)](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.16.9/)

---

## Version Information

| Component | Version |
|-----------|---------|
| **OpenShift** | 4.16.9 |
| **Kubernetes** | 1.29.x |
| **RHCOS** | 416.94.x |
| **Terraform** | 1.5.0+ |
| **wget/curl** | Any |
| **Go** | 1.22.x |
| **AWS Provider** | 5.0+ |

---

## Contact and Support

### For Issues With:

**Documentation**
- Review the specific component README
- Check SUMMARY.md for overview

**AMI Build**
- See: custom-ami-build/README.md
- Run: `./create-custom-ami.sh`
- Check: `custom-ami-result.env` for AMI ID

**Installer Build**
- See: openshift-installer-modifications.4.16/README.md
- Check build output

**Terraform Deployment**
- See: README.md Part 4
- Check: terraform-openshift-v18/output/openshift-install.log

**OpenShift Cluster**
- See: README.md Troubleshooting section
- Red Hat Support: https://access.redhat.com/

---

**Last Updated**: January 21, 2026  
**Document Version**: 1.0  
**Status**: Complete and Ready for Use
