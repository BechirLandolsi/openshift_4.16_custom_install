# Important Fixes Applied - January 22, 2026

## Issue: Import Failed - "Unsupported file format"

### Problem
AWS ImportSnapshot was receiving a **gzipped VMDK file** (`.vmdk.gz`), but it requires an **uncompressed VMDK** file.

**Error Message**:
```
Status: deleted - Progress: None%
StatusMessage: disk validation failed [unsupported specified file format]
```

### Root Cause
The script was:
1. Downloading: `rhcos-4.16.51-x86_64-aws.x86_64.vmdk.gz` (~1GB compressed)
2. Uploading compressed file to S3
3. AWS ImportSnapshot rejected the gzipped format

### Solution Applied

**Updated Script**: `create-custom-ami.sh` now:
1. Downloads: `rhcos-4.16.51-x86_64-aws.x86_64.vmdk.gz` (~1GB)
2. **Decompresses**: `gunzip -k` to create `.vmdk` file (~16GB)
3. Uploads: Uncompressed `.vmdk` file to S3
4. AWS ImportSnapshot: Accepts uncompressed VMDK

### Code Changes

```bash
# Before (WRONG):
wget rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz
aws s3 cp rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz s3://bucket/

# After (CORRECT):
wget rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz
gunzip -k rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk.gz  # Decompress
aws s3 cp rhcos-${RHCOS_VERSION}-x86_64-aws.x86_64.vmdk s3://bucket/  # Upload uncompressed
```

### Impact on Timeline

| Step | Before | After | Change |
|------|--------|-------|--------|
| Download | 2-5 min | 2-5 min | Same |
| **Decompress** | - | **1-3 min** | **New step** |
| Upload | 5-10 min (~1GB) | 10-15 min (~16GB) | +5 min |
| Import | 15-25 min | 15-25 min | Same |
| **Total** | **25-40 min** | **30-50 min** | **+5-10 min** |

### Other Fixes Applied

#### 1. vmimport Role Missing Permissions
**Issue**: Role lacked `ec2:ImportSnapshot` permission

**Fix**: Updated role policy to include:
```json
{
  "Action": [
    "ec2:ImportSnapshot",
    "ec2:DescribeImportSnapshotTasks"
  ]
}
```

#### 2. vmimport Role Can't Access KMS Key
**Issue**: Role couldn't encrypt with customer KMS key

**Fix**: Create KMS grant:
```bash
aws kms create-grant \
  --key-id "$KMS_KEY_ID" \
  --grantee-principal "arn:aws:iam::ACCOUNT_ID:role/vmimport" \
  --operations "Encrypt" "Decrypt" "GenerateDataKey" "CreateGrant" ...
```

### Files Updated

- ✅ `create-custom-ami.sh` - Added decompression step
- ✅ `README.md` - Updated all steps and troubleshooting
- ✅ `SETUP_GUIDE.md` - Updated prerequisites
- ✅ `.gitignore` - Added temporary policy files

### How to Use Updated Script

```bash
# 1. Ensure you have the updated script
cd custom-ami-build/
chmod +x create-custom-ami.sh

# 2. Set environment variables
export RHCOS_VERSION="4.16.51"
export AWS_REGION="eu-west-1"
export KMS_KEY_ID="alias/your-key"

# 3. Run (it will now decompress automatically)
./create-custom-ami.sh
```

### Disk Space Requirements

**Before running the script, ensure you have:**
- Download: ~1GB for compressed `.vmdk.gz`
- Decompressed: ~16GB for uncompressed `.vmdk`
- **Total needed**: ~17GB free space

**After AMI creation**, you can delete the uncompressed file:
```bash
rm rhcos-4.16.51-x86_64-aws.x86_64.vmdk  # Save 16GB
# Keep compressed for future use
```

### Verification

After running the updated script, verify:

```bash
# 1. Check files exist
ls -lh rhcos-*.vmdk*
# Should show:
# rhcos-4.16.51-x86_64-aws.x86_64.vmdk.gz (~1GB)
# rhcos-4.16.51-x86_64-aws.x86_64.vmdk (~16GB)

# 2. Check S3 upload
aws s3 ls s3://$S3_BUCKET_NAME/
# Should show: rhcos-4.16.51-x86_64-aws.x86_64.vmdk (not .gz)

# 3. Monitor import (should not fail with "unsupported format")
aws ec2 describe-import-snapshot-tasks \
  --region $AWS_REGION \
  --import-task-ids $IMPORT_TASK_ID
```

### Status

✅ **Fixed and Tested**  
📝 **Documentation Updated**  
🚀 **Ready for Production Use**

---

**Date**: January 22, 2026  
**Issue**: AWS ImportSnapshot unsupported file format  
**Solution**: Decompress VMDK before upload  
**Files**: create-custom-ami.sh, README.md updated
