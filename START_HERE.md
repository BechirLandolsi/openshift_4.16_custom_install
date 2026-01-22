# 🚀 OpenShift 4.16 on AWS - Start Here

## Welcome!

This folder contains everything you need to deploy OpenShift 4.16 on AWS with:

✅ **Custom AMI** with KMS encryption (Red Hat official method)  
✅ **Modified Installer** that bypasses subnet tagging requirements  
✅ **Automated Terraform** deployment with OIDC  
✅ **Complete Documentation** for all scenarios

> **Note**: Documentation updated to use Red Hat's official VMDK import process (same as your 4.14 consultant PDF). See `UPDATES_SUMMARY.md` for details

---

## 📚 Choose Your Path

### 🏃 Path 1: Fast Track (Recommended for experienced users)

**Time**: ~2 hours to working cluster

```
1. Read QUICKSTART.md (10 min)
2. Follow the 5 phases
3. Deploy cluster
```

**Start**: [QUICKSTART.md](QUICKSTART.md) ➔

---

### 📖 Path 2: Complete Understanding (Recommended for first deployment)

**Time**: ~4 hours (including reading)

```
1. Read SUMMARY.md (15 min) - Overview
2. Read README.md (45 min) - Comprehensive guide
3. Follow detailed steps
4. Deploy cluster
```

**Start**: [SUMMARY.md](SUMMARY.md) ➔ [README.md](README.md)

---

### 🎯 Path 3: Component-Specific (For specific tasks)

Choose based on what you need:

| Need | Document | Time |
|------|----------|------|
| Build custom AMI | [custom-ami-build/README.md](custom-ami-build/README.md) | 30 min |
| Build custom installer | [openshift-installer-modifications.4.16/README.md](openshift-installer-modifications.4.16/README.md) | 20 min |
| Understand structure | [INDEX.md](INDEX.md) | 10 min |

---

## 📁 What's Inside?

### Core Documentation

| File | Size | Purpose | Read Time |
|------|------|---------|-----------|
| **README.md** | Large | Complete guide | 45 min |
| **QUICKSTART.md** | Medium | Fast deployment | 10 min |
| **SUMMARY.md** | Medium | Executive summary | 15 min |
| **INDEX.md** | Medium | File navigation | 10 min |
| **START_HERE.md** | Small | This file! | 5 min |

### Component Folders

```
📁 custom-ami-build/
   └── Everything to create custom RHCOS AMI
       ✓ Automated shell script (Red Hat official method)
       ✓ Red Hat documented VMDK import process
       ✓ Build instructions

📁 openshift-installer-modifications.4.16/
   └── Modified installer source files
       ✓ 4 Go files with subnet tag bypass
       ✓ Build instructions
       ✓ Usage guide

📁 terraform-openshift-v18/
   └── Infrastructure as Code
       ✓ All Terraform files
       ✓ Installation scripts
       ✓ Configuration examples
```

---

## ⚡ Quick Start (Impatient?)

If you're confident and want to start NOW:

### Prerequisites
```bash
# Ensure you have these installed:
go version      # Must be 1.22.x
terraform -v    # Must be 1.5.0+
aws --version   # AWS CLI v2
wget --version  # For downloading RHCOS VMDK
```

### Phase 1: AMI (30-40 min)
```bash
cd custom-ami-build/
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="arn:aws:kms:eu-west-1:123456789012:key/..."
./create-custom-ami.sh
# AMI ID will be saved in custom-ami-result.env
source custom-ami-result.env
```

### Phase 2: Installer (20 min)
```bash
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer
# Copy files from openshift-installer-modifications.4.16/pkg/
./hack/build.sh
cp bin/openshift-install ../terraform-openshift-v18/
```

### Phase 3: Deploy (45 min)
```bash
cd terraform-openshift-v18/
# Edit env/my-cluster.tfvars with your configuration
terraform init
terraform apply -var-file="env/my-cluster.tfvars"
# Monitor: tail -f output/openshift-install.log
```

### Phase 4: Verify
```bash
export KUBECONFIG=installer-files/auth/kubeconfig
oc get nodes
oc get co
oc whoami --show-console
```

**Done!** ✅

---

## 🎯 What Problem Does This Solve?

### Customer's Challenge

The customer needs to deploy OpenShift 4.16 on AWS but faces these constraints:

1. ❌ **Cannot tag shared subnets** (IAM permission restrictions)
2. ❌ **Must use custom AMI** (KMS encryption required)
3. ❌ **Shared VPC environment** (multiple clusters, central network management)
4. ⚠️ **Possibly air-gapped** (disconnected from internet)

### Our Solution

1. ✅ **Modified OpenShift installer** that skips subnet tagging
2. ✅ **Red Hat official VMDK import** to create custom AMI with KMS encryption
3. ✅ **Terraform automation** for reproducible deployments
4. ✅ **Complete guide** for disconnected installations

---

## 🔑 Key Features

### Modified OpenShift Installer

**Environment Variables**:
```bash
# During installation:
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="abc12"

# During deletion:
export SkipDestroyingSharedTags=On
```

**What it does**: Continues installation even when subnet tagging fails

### Custom AMI

**Built with**:
- ✅ KMS encryption (compliance)
- ✅ RHCOS 4.16 base (compatibility)
- ✅ Red Hat official VMDK import method

**Build time**: ~30-40 minutes (AWS import process)

**Note**: IMDSv2 is configured at launch-time (not in AMI)

### Terraform Automation

**Manages**:
- IAM roles with permission boundaries
- S3 buckets for OIDC
- OpenShift cluster deployment
- DNS configuration
- Day 2 operations

---

## 📊 Timeline

| Phase | Duration | Details |
|-------|----------|---------|
| **Reading** | 10-45 min | Depends on path chosen |
| **AMI Build** | 30 min | Can parallelize with installer |
| **Installer Build** | 20 min | Can parallelize with AMI |
| **Terraform Config** | 15 min | After AMI complete |
| **Cluster Deploy** | 45 min | Automated by Terraform |
| **Verification** | 5 min | Check cluster health |
| **TOTAL** | **2-3 hours** | Less if parallelized |

---

## 🆘 Getting Help

### Quick Reference

| Issue | Solution |
|-------|----------|
| Tag permission errors | Check environment variables are set |
| AMI not found | Verify AMI ID and region |
| Bootstrap timeout | Check logs: `tail -f output/openshift-install.log` |
| Nodes not ready | Approve CSRs: `oc get csr \| grep Pending` |

### Full Troubleshooting

See **README.md → Troubleshooting Section** for:
- Common issues and solutions
- Debug commands
- Log locations
- Support resources

---

## 📋 Requirements Checklist

Before starting, ensure you have:

### Tools Installed
- [ ] Go 1.22.x
- [ ] Terraform 1.5.0+
- [ ] wget or curl
- [ ] AWS CLI v2
- [ ] oc client 4.16+
- [ ] jq

### AWS Resources
- [ ] VPC with private subnets
- [ ] Route53 hosted zone
- [ ] KMS key for encryption
- [ ] IAM permissions

### Files Obtained
- [ ] Red Hat pull secret
- [ ] RHCOS source AMI ID
- [ ] AWS credentials configured

---

## 🎓 Learning Path

### For Beginners

1. **Start**: Read [SUMMARY.md](SUMMARY.md) to understand what we're building
2. **Then**: Read [README.md](README.md) → "Overview" and "Architecture"
3. **Next**: Follow [README.md](README.md) step by step
4. **Finally**: Deploy in development environment first

### For Experienced Users

1. **Start**: Read [QUICKSTART.md](QUICKSTART.md)
2. **Do**: Follow the 5 phases
3. **Reference**: Use [README.md](README.md) for details as needed

### For Maintainers

1. **Read**: [SUMMARY.md](SUMMARY.md) for overview
2. **Study**: [INDEX.md](INDEX.md) for file structure
3. **Reference**: Component READMEs for specific tasks
4. **Bookmark**: Troubleshooting sections

---

## 🔗 Quick Links

### Essential Documents
- 📘 [Complete Guide (README.md)](README.md)
- ⚡ [Quick Start (QUICKSTART.md)](QUICKSTART.md)
- 📋 [Summary (SUMMARY.md)](SUMMARY.md)
- 📑 [File Index (INDEX.md)](INDEX.md)

### Component Guides
- 🖼️ [AMI Build Guide](custom-ami-build/README.md)
- 🔧 [Installer Modifications](openshift-installer-modifications.4.16/README.md)

### External Resources
- 🌐 [OpenShift 4.16 Docs](https://docs.openshift.com/container-platform/4.16/)
- 🔑 [Red Hat Pull Secret](https://console.redhat.com/openshift/install/pull-secret)
- 💿 [RHCOS AMI List](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.16/)

---

## 💡 Tips for Success

### Before You Start

1. **Test in Development First**
   - Deploy in dev/staging before production
   - Validate all steps work in your environment
   - Document any custom requirements

2. **Gather Information**
   - List all AWS resource IDs (VPC, subnets, KMS key)
   - Confirm proxy settings if air-gapped
   - Identify Route53 hosted zone

3. **Allocate Time**
   - Block 3-4 hours for first deployment
   - Have team member available for questions
   - Plan for verification and testing

### During Deployment

1. **Monitor Logs**
   - Keep `tail -f output/openshift-install.log` running
   - Watch for errors or warnings
   - Save logs for troubleshooting

2. **Verify Each Phase**
   - AMI: Check IMDSv2 and encryption
   - Installer: Test version command
   - Terraform: Review plan before apply

3. **Don't Panic**
   - Bootstrap can take 20+ minutes
   - Some warnings are normal
   - Check troubleshooting guide first

### After Deployment

1. **Verify Everything**
   - All nodes ready
   - All operators available
   - Console accessible
   - DNS resolving

2. **Secure the Cluster**
   - Change kubeadmin password
   - Configure identity provider
   - Set up RBAC

3. **Document Your Setup**
   - Save configuration files
   - Note any customizations
   - Update runbooks

---

## 🎯 Success Criteria

You'll know you're successful when:

- ✅ Custom AMI created with IMDSv2 and KMS
- ✅ Custom installer built and working
- ✅ Terraform applies without errors
- ✅ All nodes show "Ready" status
- ✅ All cluster operators "Available"
- ✅ Console accessible with credentials
- ✅ No tagging errors during install/destroy

---

## 🤝 Support

### Documentation Issues
- Check [INDEX.md](INDEX.md) for navigation
- Review component-specific READMEs
- Refer to troubleshooting sections

### Technical Issues
- See README.md → Troubleshooting
- Check OpenShift documentation
- Contact Red Hat support (mention custom modifications)

### Questions About Approach
- Review [SUMMARY.md](SUMMARY.md) for rationale
- Check "Why These Modifications?" section
- Review alternative solutions in README.md

---

## 🚦 Decision Matrix

### Which document should I read?

```
Do you need to deploy NOW and know OpenShift well?
    YES → QUICKSTART.md
    NO  ↓

Is this your first OpenShift 4.16 deployment?
    YES → README.md (full guide)
    NO  ↓

Do you need to present to management?
    YES → SUMMARY.md
    NO  ↓

Looking for a specific file?
    YES → INDEX.md
    NO  ↓

Need to understand modifications?
    YES → openshift-installer-modifications.4.16/README.md
    NO  ↓

Need to build AMI?
    YES → custom-ami-build/README.md
```

---

## 📞 Next Steps

### Right Now (5 minutes)
1. ✅ Choose your path (Fast Track vs Complete)
2. ✅ Check prerequisites checklist
3. ✅ Open the appropriate document

### Today (2-3 hours)
1. ✅ Build custom AMI
2. ✅ Build custom installer
3. ✅ Configure Terraform
4. ✅ Deploy cluster

### This Week
1. ✅ Verify cluster health
2. ✅ Configure identity provider
3. ✅ Deploy test applications
4. ✅ Plan Day 2 operations

---

## 🎉 You're Ready!

Pick your path above and start deploying OpenShift 4.16 with confidence.

**Remember**: 
- 📘 Full details in README.md
- ⚡ Fast track in QUICKSTART.md
- 🆘 Help in Troubleshooting section

Good luck! 🚀

---

**Document**: START_HERE.md  
**Version**: 1.0  
**Date**: January 21, 2026  
**OpenShift**: 4.16.9
