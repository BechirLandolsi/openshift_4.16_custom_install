# OpenShift 4.16 on AWS - Quick Start Guide

## Prerequisites Checklist

- [ ] AWS account with appropriate permissions
- [ ] Go 1.22.x installed
- [ ] Terraform 1.5.0+ installed
- [ ] wget or curl installed
- [ ] Red Hat pull secret obtained
- [ ] Existing VPC with private subnets
- [ ] Route53 hosted zone
- [ ] KMS key for encryption

## Phase 1: Create Custom AMI (30-40 minutes)

```bash
# Set environment variables
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/your-key-id"
# Or: export KMS_KEY_ID="alias/plaasma-ec2-cmk"

# Run automated AMI creation script
cd Openshift_4.16/custom-ami-build/
./create-custom-ami.sh

# Script will:
# - Download RHCOS VMDK (~5 min)
# - Upload to S3 (~10 min)
# - Import as encrypted snapshot (~20 min)
# - Register AMI (~1 min)
# - Save results to custom-ami-result.env

# Source the results
source custom-ami-result.env
echo "Your Custom AMI: $CUSTOM_AMI"
```

## Phase 2: Build Custom Installer (20 minutes)

```bash
# Install Go 1.22.x if needed
go version  # Should be 1.22.x

# Clone OpenShift installer
cd ~/openshift-build
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer

# Apply modifications
MODS="/path/to/Openshift_4.16/openshift-installer-modifications.4.16"
for file in \
  "pkg/asset/cluster/aws/aws.go" \
  "pkg/asset/installconfig/clusterid.go" \
  "pkg/destroy/aws/shared.go" \
  "pkg/asset/releaseimage/default.go"; do
  cp "$file" "${file}.original"
  cp "${MODS}/${file}" "${file}"
done

# Build
./hack/build.sh

# Copy to terraform directory
cp bin/openshift-install /path/to/Openshift_4.16/terraform-openshift-v18/
```

## Phase 3: Configure Terraform (15 minutes)

```bash
cd /path/to/Openshift_4.16/terraform-openshift-v18/

# Create your tfvars file
cp env/ocp-skw-hprod-plaasma-bkprestore-d44a5.tfvars env/my-cluster.tfvars

# Edit env/my-cluster.tfvars - Update these critical values:
# - account_id
# - region
# - vpc_id
# - cluster_name
# - infra_random_id (5 characters, e.g., "abc12")
# - ami (from Phase 1)
# - domain
# - hosted_zone
# - aws_private_subnets
# - kms_ec2_alias
# - All IAM role names (make unique per cluster)

# Prepare pull secret
mkdir -p openshift
# Download from: https://console.redhat.com/openshift/install/pull-secret
cp /path/to/pull-secret.txt openshift/openshift_pull_secret.json

# Initialize Terraform
terraform init
```

## Phase 4: Deploy Cluster (40-50 minutes)

```bash
# Still in terraform-openshift-v18/

# Plan
terraform plan -var-file="env/my-cluster.tfvars" -out=tfplan

# Review the plan carefully

# Apply
terraform apply tfplan

# Monitor progress (in another terminal)
tail -f output/openshift-install.log
```

## Phase 5: Verify Installation (5 minutes)

```bash
# Set kubeconfig
export KUBECONFIG="$(pwd)/installer-files/auth/kubeconfig"

# Check cluster
oc get clusterversion
oc get nodes
oc get co

# Get console credentials
echo "Console: $(oc whoami --show-console)"
echo "Username: kubeadmin"
echo "Password: $(cat installer-files/auth/kubeadmin-password)"
```

## Quick Reference: Environment Variables

### For Installation (in create-cluster.sh):
```bash
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="abc12"  # Must match tfvars
```

### For Deletion (in delete-cluster.sh):
```bash
export SkipDestroyingSharedTags=On
```

## Troubleshooting Quick Fixes

### Issue: Tag Permission Errors
```bash
# Ensure environment variables are set
echo $IgnoreErrorsOnSharedTags  # Should be "On"
```

### Issue: Bootstrap Timeout
```bash
# Check logs
tail -100 output/openshift-install.log
# Check bootstrap node
# Look for ignition errors
```

### Issue: Nodes Not Ready
```bash
# Approve pending CSRs
oc get csr | grep Pending
oc get csr -o name | xargs oc adm certificate approve
```

## File Structure Reference

```
Openshift_4.16/
├── README.md                           # ← Complete documentation
├── QUICKSTART.md                       # ← This file
├── custom-ami-build/                   # ← Phase 1
│   ├── rhcos-4.16-custom.pkr.hcl
│   ├── variables.pkrvars.hcl.example
│   └── README.md
├── openshift-installer-modifications.4.16/  # ← Phase 2
│   ├── README.md
│   └── pkg/
│       ├── asset/
│       └── destroy/
└── terraform-openshift-v18/            # ← Phase 3 & 4
    ├── *.tf files
    ├── *.sh scripts
    └── env/
        └── your-cluster.tfvars
```

## Timeline Summary

| Phase | Duration | Can be Done in Parallel? |
|-------|----------|-------------------------|
| AMI Build | 30 min | ✅ Yes (with Installer Build) |
| Installer Build | 20 min | ✅ Yes (with AMI Build) |
| Terraform Config | 15 min | ❌ Needs AMI ID |
| Cluster Deploy | 45 min | ❌ Sequential |
| Verification | 5 min | ❌ After deployment |
| **Total** | **~2 hours** | (or ~1 hour if parallelized) |

## Key URLs

- **Complete Guide**: `./README.md`
- **AMI Details**: `./custom-ami-build/README.md`
- **Installer Mods**: `./openshift-installer-modifications.4.16/README.md`
- **Red Hat Pull Secret**: https://console.redhat.com/openshift/install/pull-secret
- **RHCOS AMI List**: https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/

## Critical Values to Customize

Before running, ensure these are updated in `env/my-cluster.tfvars`:

```hcl
cluster_name        = "my-cluster"           # YOUR CLUSTER NAME
infra_random_id     = "abc12"                # 5 CHARS - MUST MATCH ENV VAR
ami                 = "ami-your-custom-ami"  # FROM PHASE 1
region              = "eu-west-1"            # YOUR REGION
vpc_id              = "vpc-xxx"              # YOUR VPC
aws_private_subnets = ["subnet-xxx", ...]    # YOUR SUBNETS
hosted_zone         = "Zxxx"                 # YOUR ROUTE53 ZONE
domain              = "example.com"          # YOUR DOMAIN
kms_ec2_alias       = "alias/your-kms"       # YOUR KMS KEY

# Make these unique per cluster:
s3_bucket_name_oidc         = "ocp-oidc-my-cluster"
control_plane_role_name     = "ocpcontrolplane-my-cluster-iam-role"
aws_worker_iam_role         = "ocpworkernode-my-cluster-iam-role"
ocpcontrolplane_policy      = "ocpcontrolplane-policy-my-cluster"
ocpworkernode_policy        = "ocpworkernode-policy-my-cluster"
```

## Next Steps After Installation

1. **Change Admin Password**
   ```bash
   oc create secret generic kubeadmin \
     --from-literal=password=$(openssl rand -base64 32) \
     -n kube-system
   ```

2. **Configure Identity Provider**
   - LDAP, SAML, or OAuth integration
   - See: https://docs.openshift.com/container-platform/4.16/authentication/

3. **Install Operators**
   - Logging (OpenShift Logging)
   - Monitoring (enhanced)
   - Storage (ODF, EFS CSI)

4. **Configure Day 2 Operations**
   - Backup (OADP/Velero)
   - Certificate management
   - Cluster autoscaling

## Support Resources

- **Full Documentation**: See `README.md` in this directory
- **OpenShift Docs**: https://docs.openshift.com/container-platform/4.16/
- **Red Hat Support**: https://access.redhat.com/
- **OpenShift Commons**: https://commons.openshift.org/

---

**Remember**: This is a custom installation with modified components. Always document your specific configuration and modifications for support purposes.
