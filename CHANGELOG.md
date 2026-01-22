# OpenShift 4.16 Documentation - Changelog

## Version 2.0 - January 21, 2026

### Major Changes: Switched to Red Hat Official AMI Creation Method

**Summary**: Updated documentation to use Red Hat's official VMDK import process instead of Packer-based approach.

### Why This Change?

1. **Official Red Hat Support**: The VMDK import method is documented and supported by Red Hat
2. **Customer's Existing Process**: Customer already received this procedure from Red Hat consultant for 4.14
3. **Simplification**: Removed unnecessary Packer dependency
4. **IMDSv2 Clarification**: Corrected documentation to explain that IMDSv2 is a launch-time setting, not an AMI property

### What Changed

#### Files Removed
- ❌ `custom-ami-build/rhcos-4.16-custom.pkr.hcl` (Packer template - 266 lines)
- ❌ `custom-ami-build/variables.pkrvars.hcl.example` (Packer config)

#### Files Added
- ✅ `custom-ami-build/create-custom-ami.sh` (Automated shell script - 200 lines)
- ✅ `custom-ami-build/.gitignore` (Ignore downloaded files)
- ✅ `CHANGELOG.md` (This file)

#### Files Updated
- ✅ `README.md` - Part 1: Custom AMI Creation (complete rewrite)
- ✅ `QUICKSTART.md` - Updated Phase 1 commands
- ✅ `SUMMARY.md` - Updated AMI build description
- ✅ `INDEX.md` - Updated file references and commands
- ✅ `START_HERE.md` - Updated prerequisites and phase 1
- ✅ `FILES_DELIVERED.txt` - Updated file list
- ✅ `custom-ami-build/README.md` - Complete rewrite with official method

### Key Technical Corrections

#### IMDSv2 Configuration
**Previous (Incorrect)**:
- Stated IMDSv2 was "baked into" the AMI
- Suggested AMI enforces IMDSv2

**Current (Correct)**:
- IMDSv2 is a **launch-time instance setting**
- Configured in `install-config.yaml` and machine sets
- **NOT** an AMI property
- Same configuration required for both custom and standard AMIs

#### AMI Creation Method
**Previous**: Packer-based rebuild of existing Red Hat AMI
**Current**: Red Hat official VMDK import with KMS encryption

| Aspect | Packer Method | VMDK Import Method |
|--------|--------------|-------------------|
| **Source** | Existing Red Hat AMI | RHCOS VMDK file |
| **Method** | Packer rebuild | AWS import-snapshot |
| **Documentation** | Custom/Unofficial | Red Hat official |
| **Support** | ⚠️ Limited | ✅ Full Red Hat support |
| **Complexity** | Higher (Packer dependency) | Lower (AWS CLI only) |
| **Build Time** | ~15 min | ~30-40 min (AWS processing) |

### Benefits of This Change

1. **Red Hat Support Compatibility**
   - Uses documented, supported process
   - Matches customer's 4.14 procedure
   - Easier to get support if issues arise

2. **Simplified Prerequisites**
   - No Packer installation required
   - AWS CLI only (already required)
   - Fewer tools to manage

3. **Accurate Documentation**
   - Corrects IMDSv2 misconception
   - Aligns with Red Hat best practices
   - Matches official documentation

4. **Process Consistency**
   - Same method for 4.14 → 4.16 → 4.17
   - Customer already familiar with process
   - PDF from consultant remains applicable

### Migration Guide (If You Started with v1.0)

If you already built an AMI using the Packer method:

**Good News**: Your AMI works fine! No need to rebuild.

**For Future Builds**:
1. Delete Packer files (already removed)
2. Use `create-custom-ami.sh` script
3. Follow updated documentation

### New Workflow Summary

```bash
# Phase 1: Create Custom AMI (30-40 min)
cd Openshift_4.16/custom-ami-build/
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh
source custom-ami-result.env

# Phase 2: Build Installer (20 min)
# ... unchanged ...

# Phase 3: Deploy (45 min)
# ... unchanged ...
```

### Documentation Structure (Unchanged)

All documents remain in place with updated content:
- ✅ README.md (main guide)
- ✅ QUICKSTART.md (fast track)
- ✅ SUMMARY.md (executive summary)
- ✅ INDEX.md (file navigation)
- ✅ START_HERE.md (entry point)

### Reference Links

- [Red Hat Official AMI Upload Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installing_on_aws/installer-provisioned-infrastructure#installation-aws-upload-custom-rhcos-ami_installing-aws-secret-region)
- [RHCOS Downloads](https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.16/)
- [AWS Import/Export Guide](https://docs.aws.amazon.com/vm-import/latest/userguide/)

### Questions?

If you have questions about this change:
1. Read the updated `custom-ami-build/README.md`
2. Review "Understanding IMDSv2 Configuration" section
3. Compare with your Red Hat consultant's PDF for 4.14

---

## Version History

### Version 2.0 - January 21, 2026
- Switched to Red Hat official VMDK import method
- Corrected IMDSv2 documentation
- Removed Packer dependency
- Simplified AMI creation process

### Version 1.0 - January 21, 2026
- Initial release
- Packer-based AMI creation
- Complete OpenShift 4.16 installation guide

---

**Current Version**: 2.0  
**Status**: Production Ready  
**Method**: Red Hat Official (Fully Supported)
