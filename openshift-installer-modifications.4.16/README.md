# OpenShift Installer 4.16 - Custom Modifications

## Overview

This directory contains modified source files for the OpenShift 4.16 installer to address specific deployment constraints:

1. **Bypass subnet tagging permission requirements**
2. **Control InfraID generation for Terraform integration**
3. **Skip shared resource tag cleanup during deletion**
4. **Pin to specific OpenShift release version**

## Files Modified

### 1. `pkg/asset/cluster/aws/aws.go`

**Purpose**: Skip errors when tagging shared subnets/VPC resources

**Modification** (lines 81-84):
```go
ignore := os.Getenv("IgnoreErrorsOnSharedTags")
if ignore != "" {
    return nil
}
```

**Usage**:
```bash
export IgnoreErrorsOnSharedTags=On
openshift-install create cluster --dir=installer-files
```

### 2. `pkg/asset/installconfig/clusterid.go`

**Purpose**: Control the random suffix of InfraID for predictable infrastructure naming

**Modification** (lines 79-82):
```go
rand := os.Getenv("ForceOpenshiftInfraIDRandomPart")
if rand == "" {
    rand = utilrand.String(randomLen)
}
return fmt.Sprintf("%s-%s", base, rand)
```

**Usage**:
```bash
export ForceOpenshiftInfraIDRandomPart="abc12"
openshift-install create cluster --dir=installer-files
# Results in InfraID: cluster-name-abc12
```

### 3. `pkg/destroy/aws/shared.go`

**Purpose**: Skip tag removal from shared resources during cluster deletion

**Modification** (lines 56-59 and 118-124):
```go
skip := os.Getenv("SkipDestroyingSharedTags")
if skip != "" {
    return nil
}

// Later in the code...
ignore := os.Getenv("IgnoreErrorsOnSharedTags")
if ignore == "" {
    nextTagClients = append(nextTagClients, tagClient)
}
```

**Usage**:
```bash
export SkipDestroyingSharedTags=On
openshift-install destroy cluster --dir=installer-files
```

### 4. `pkg/asset/releaseimage/default.go`

**Purpose**: Pin installer to specific OpenShift release version

**Modification** (line 24):
```go
defaultReleaseImageOriginal = "quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64"
```

**Usage**: Automatic (no environment variable needed)

## Building the Custom Installer

### Prerequisites

- Go 1.22.x or later
- Git
- ~10 GB free disk space
- Linux or macOS (Windows via WSL2)

### Build Steps

```bash
# 1. Clone OpenShift installer repository
git clone https://github.com/openshift/installer.git -b release-4.16
cd installer

# 2. Backup original files
for file in \
  "pkg/asset/cluster/aws/aws.go" \
  "pkg/asset/installconfig/clusterid.go" \
  "pkg/destroy/aws/shared.go" \
  "pkg/asset/releaseimage/default.go"; do
  cp "$file" "${file}.original"
done

# 3. Copy modified files (from this directory)
MODIFICATIONS_DIR="/path/to/Openshift_4.16/openshift-installer-modifications.4.16"
cp "${MODIFICATIONS_DIR}/pkg/asset/cluster/aws/aws.go" pkg/asset/cluster/aws/aws.go
cp "${MODIFICATIONS_DIR}/pkg/asset/installconfig/clusterid.go" pkg/asset/installconfig/clusterid.go
cp "${MODIFICATIONS_DIR}/pkg/destroy/aws/shared.go" pkg/destroy/aws/shared.go
cp "${MODIFICATIONS_DIR}/pkg/asset/releaseimage/default.go" pkg/asset/releaseimage/default.go

# 4. Build
./hack/build.sh

# 5. Verify
bin/openshift-install version
```

### Expected Output

```
bin/openshift-install 4.16.9
built from commit xxxxxx
release image quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64
release architecture amd64
```

## Installation Usage

### Standard Installation with Modifications

```bash
# Set environment variables
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="abc12"

# Run installer
openshift-install create cluster --dir=installer-files --log-level=debug
```

### Cluster Deletion with Modifications

```bash
# Set environment variables
export SkipDestroyingSharedTags=On

# Run destroyer
openshift-install destroy cluster --dir=installer-files --log-level=debug
```

### Integration with Terraform

In `create-cluster.sh`:
```bash
#!/bin/bash
export IgnoreErrorsOnSharedTags=On
export ForceOpenshiftInfraIDRandomPart="${INFRA_RANDOM_ID}"
./openshift-install create cluster --dir=installer-files --log-level=debug
```

In `delete-cluster.sh`:
```bash
#!/bin/bash
export SkipDestroyingSharedTags=On
./openshift-install destroy cluster --dir=installer-files --log-level=debug
```

## Why These Modifications?

### Problem: Shared Infrastructure Constraints

In enterprise AWS environments:

1. **Shared VPCs and Subnets**: Multiple clusters deployed in centrally-managed networking
2. **Restricted IAM Permissions**: Cannot tag shared resources due to organizational policies
3. **Infrastructure as Code**: Terraform manages resources and needs predictable naming
4. **Multiple Clusters**: Same infrastructure hosts multiple OpenShift deployments

### Standard Installer Behavior (Without Modifications)

```
Install → Tag Subnets → ❌ Permission Denied → Installation Fails
Destroy → Untag Subnets → ❌ Permission Denied → Deletion Stuck
```

### Modified Installer Behavior

```
Install → Tag Subnets → ⚠️ Permission Denied → ✅ Continue Installation
Destroy → Skip Untag → ✅ Clean Deletion (preserves shared resources)
```

## Environment Variables Reference

| Variable | Phase | Effect | Required |
|----------|-------|--------|----------|
| `IgnoreErrorsOnSharedTags` | Create | Skip tag errors on shared resources | Yes (in shared VPC) |
| `ForceOpenshiftInfraIDRandomPart` | Create | Set InfraID suffix | Yes (for Terraform) |
| `SkipDestroyingSharedTags` | Destroy | Skip tag cleanup | Yes (in shared VPC) |

## Differences from OpenShift 4.14

| Aspect | 4.14 | 4.16 |
|--------|------|------|
| **Go Version** | 1.20.10 | 1.22.x |
| **Release Image** | 4.14.21 | 4.16.9 |
| **Modifications** | Same 4 files | Same 4 files |
| **Code Changes** | ~23 lines | ~23 lines |
| **Build Time** | ~5-10 min | ~5-10 min |

The modifications are nearly identical between versions, only the OpenShift release version changes.

## Verification

After building, verify modifications are present:

```bash
# Check aws.go
grep -n "IgnoreErrorsOnSharedTags" pkg/asset/cluster/aws/aws.go
# Should output line numbers: 81, 82

# Check clusterid.go
grep -n "ForceOpenshiftInfraIDRandomPart" pkg/asset/installconfig/clusterid.go
# Should output line numbers: 79

# Check shared.go
grep -n "SkipDestroyingSharedTags" pkg/destroy/aws/shared.go
# Should output line numbers: 56

# Check default.go
grep -n "4.16.9" pkg/asset/releaseimage/default.go
# Should output line number: 24
```

## Troubleshooting

### Build Fails: Go Version Too Old

```bash
go version
# If < 1.22, install newer Go:
wget https://go.dev/dl/go1.22.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
```

### Build Fails: Module Errors

```bash
# Clean and retry
rm -rf vendor/ go.mod.bak go.sum.bak
./hack/build.sh
```

### Installer Still Fails on Tagging

**Check environment variables are set**:
```bash
echo $IgnoreErrorsOnSharedTags
# Should output: On

# If using Terraform, check the script exports them
cat create-cluster.sh | grep export
```

## Security Considerations

### Support Impact

⚠️ **Important**: Using a modified installer may complicate Red Hat support cases. Always mention the modifications when opening support tickets.

### Upgrade Path

When upgrading to newer OpenShift versions:

1. Clone new release branch: `git clone ... -b release-4.17`
2. Reapply modifications (may need adjustment for code changes)
3. Test in development environment first
4. Document any new changes required

### Alternative Solutions

If you can modify IAM permissions:

**Option A**: Grant tagging permissions (preferred)
```json
{
  "Effect": "Allow",
  "Action": ["ec2:CreateTags", "ec2:DeleteTags"],
  "Resource": "arn:aws:ec2:*:*:subnet/*",
  "Condition": {
    "StringLike": {
      "aws:RequestTag/kubernetes.io/cluster/*": ["owned", "shared"]
    }
  }
}
```

**Option B**: Pre-tag resources before installation
```bash
aws ec2 create-tags --resources subnet-xxx \
  --tags Key=kubernetes.io/cluster/cluster-name,Value=shared
```

## Version Information

- **OpenShift Version**: 4.16.9
- **Installer Branch**: release-4.16
- **Go Version Required**: 1.22.x
- **Modification Version**: 1.0
- **Last Updated**: January 21, 2026

## References

- [OpenShift 4.16 Installation Guide](https://docs.openshift.com/container-platform/4.16/installing/)
- [OpenShift Installer GitHub](https://github.com/openshift/installer/tree/release-4.16)
- [AWS Installation Prerequisites](https://docs.openshift.com/container-platform/4.16/installing/installing_aws/installing-aws-account.html)

## License

These modifications are based on the OpenShift installer which is licensed under Apache License 2.0.

---

**Note**: Keep this README updated when applying modifications to newer OpenShift versions.
