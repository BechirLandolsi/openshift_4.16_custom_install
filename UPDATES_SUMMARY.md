# Documentation Update Summary

**Date**: January 21, 2026  
**Version**: 2.0  
**Update Type**: AMI Creation Method Change

---

## What Changed?

### Switched from Packer to Red Hat Official VMDK Import

**Reason**: Customer asked why we don't use Red Hat's documented process (which they already have from their 4.14 consultant).

**Answer**: We should! The Red Hat official method is better for this use case.

---

## Quick Comparison

| Aspect | Old (v1.0) | New (v2.0) |
|--------|-----------|-----------|
| **Method** | Packer rebuild | Red Hat VMDK import |
| **Documentation** | Custom | Official Red Hat |
| **Support** | Limited | Full Red Hat support |
| **Prerequisites** | Packer + AWS CLI | AWS CLI only |
| **Build Time** | ~15 min | ~30-40 min |
| **Complexity** | Higher | Lower |
| **Files** | 2 files (template+config) | 1 file (script) |

---

## Key Correction: IMDSv2 Understanding

### Previous Documentation (Incorrect)
- Stated IMDSv2 was "enforced from instance creation"
- Implied IMDSv2 was "baked into the AMI"
- Suggested custom AMI provides IMDSv2

### Updated Documentation (Correct)
- IMDSv2 is a **launch-time setting**, not AMI property
- Configured in `install-config.yaml` and machine sets
- Same for both custom and standard AMIs
- Custom AMI only provides **KMS encryption**

**Configuration Location**:
```yaml
# In install-config.yaml or machine sets
metadataService:
  authentication: Required  # This enforces IMDSv2
```

---

## What You Need to Know

### If You Haven't Started Yet
✅ **Use the new process** - just follow the updated documentation

### If You Already Built AMI with Packer (v1.0)
✅ **Your AMI works fine** - no need to rebuild  
✅ **Still configure IMDSv2** in install-config.yaml (same as before)  
✅ **For next AMI** - use the new script method

### If You're In Middle of Installation
✅ **Continue** - both methods produce compatible AMIs  
✅ **IMDSv2 config** is the same regardless of AMI creation method

---

## Updated Files

### Major Rewrites
- `README.md` - Part 1 (Custom AMI Creation)
- `custom-ami-build/README.md` - Complete rewrite

### Files Added
- `custom-ami-build/create-custom-ami.sh` - Automated script
- `custom-ami-build/.gitignore` - Git ignore rules
- `CHANGELOG.md` - Detailed changelog
- `UPDATES_SUMMARY.md` - This file

### Files Removed
- `custom-ami-build/rhcos-4.16-custom.pkr.hcl` - Packer template
- `custom-ami-build/variables.pkrvars.hcl.example` - Packer config

### Files Updated
- `QUICKSTART.md` - Phase 1 commands
- `SUMMARY.md` - AMI build description
- `INDEX.md` - File references
- `START_HERE.md` - Prerequisites
- `FILES_DELIVERED.txt` - File inventory

---

## New AMI Creation Process

### Quick Version
```bash
cd Openshift_4.16/custom-ami-build/
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh
source custom-ami-result.env
```

### What the Script Does
1. Downloads RHCOS VMDK from Red Hat mirror
2. Creates S3 bucket
3. Uploads VMDK to S3
4. Imports as encrypted EBS snapshot (with KMS)
5. Registers AMI from snapshot
6. Tags resources
7. Saves AMI ID to `custom-ami-result.env`

### Manual Alternative
Full manual steps documented in `custom-ami-build/README.md`

---

## Why This Is Better

### 1. Red Hat Support
- ✅ Official documented method
- ✅ Same as consultant provided for 4.14
- ✅ Easier to get support

### 2. Consistency
- ✅ Same process for all versions (4.14, 4.16, 4.17)
- ✅ Customer already familiar
- ✅ PDF documentation remains valid

### 3. Simplicity
- ✅ One script vs complex Packer template
- ✅ Fewer dependencies (no Packer)
- ✅ Standard AWS CLI operations

### 4. Transparency
- ✅ Clear what each step does
- ✅ Can run manually if needed
- ✅ Easy to troubleshoot

---

## IMDSv2 Configuration (Important!)

### Where IMDSv2 is Actually Configured

**Option 1: In install-config.yaml (for initial installation)**
```yaml
apiVersion: v1
baseDomain: example.com
controlPlane:
  platform:
    aws:
      metadataService:
        authentication: Required  # Enforces IMDSv2
compute:
- name: worker
  platform:
    aws:
      metadataService:
        authentication: Required  # Enforces IMDSv2
```

**Option 2: In Terraform templates.tf (for your deployment)**

Update the install-config template to include:
```yaml
compute:
- hyperthreading: Enabled
  name: worker
  platform:
    aws:
      metadataService:
        authentication: Required  # Enforces IMDSv2
```

**Option 3: In Machine Sets (for Day 2 operations)**
```yaml
spec:
  template:
    spec:
      providerSpec:
        value:
          metadataServiceOptions:
            authentication: Required
```

### Verification After Cluster Deploy

```bash
# Check all instances have IMDSv2 required
CLUSTER_TAG="kubernetes.io/cluster/${CLUSTER_NAME}-${INFRA_RANDOM_ID}"
aws ec2 describe-instances \
  --filters "Name=tag:${CLUSTER_TAG},Values=owned" \
  --query 'Reservations[].Instances[].[InstanceId,MetadataOptions.HttpTokens]' \
  --output table

# All should show "required"
```

---

## Timeline Impact

| Phase | Old Time | New Time | Difference |
|-------|----------|----------|------------|
| AMI Build | 15 min | 30-40 min | +15-25 min |
| Other Phases | Same | Same | No change |
| **Total** | ~1.75 hours | ~2 hours | +15-25 min |

The slightly longer build time is due to AWS snapshot import processing (which you cannot speed up).

---

## Action Items

### For Documentation Users

1. ✅ Re-read `custom-ami-build/README.md`
2. ✅ Note the IMDSv2 clarification
3. ✅ Update any local procedures to use new script

### For Active Deployments

1. ✅ If AMI already built - continue as planned
2. ✅ If AMI not built - use new script method
3. ✅ Ensure IMDSv2 configured in install-config.yaml

### For Future Versions

1. ✅ Same process for OpenShift 4.17+
2. ✅ Just update RHCOS_VERSION variable
3. ✅ Script handles everything else

---

## References

- [Red Hat OpenShift 4.16 - Uploading Custom RHCOS AMI](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-upload-custom-rhcos-ami_installing-aws-secret-region)
- [RHCOS 4.16 Downloads](https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/)
- [AWS VM Import/Export Documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/)

---

## Questions?

**Q: Why did this change?**  
A: Customer asked why we don't use Red Hat's documented process. They're right - we should use the official method.

**Q: Do I need to rebuild my AMI?**  
A: No, if you already have one. Both methods produce valid AMIs.

**Q: Is Packer method wrong?**  
A: No, but Red Hat's method is better for support and consistency with customer's existing 4.14 process.

**Q: Where is IMDSv2 really configured?**  
A: In `install-config.yaml` and machine sets, NOT in the AMI. This is the same for all AMIs.

**Q: What about my PDF from Red Hat consultant?**  
A: It's now directly applicable! The new process matches what's in your PDF (just update version numbers).

---

**Document Version**: 2.0  
**Status**: Complete and Accurate  
**Method**: Red Hat Official (Fully Supported)
