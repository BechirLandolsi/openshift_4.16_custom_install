# Customer Tags Simulation - Immutable Subnet Tags Testing

## 📂 What's in This Folder?

This folder contains all the tools you need to simulate your customer's environment where subnet tags are pre-tagged and immutable (cannot be modified).

## 🎯 Purpose

Test if your OpenShift installation can bypass tag errors when:
- Subnets are already tagged with OpenShift-required tags
- IAM policies prevent OpenShift from modifying subnet tags
- This simulates a restricted customer environment

**Important:** These scripts do NOT modify your Terraform configuration. Everything is done via AWS CLI outside of Terraform.

## 📁 Files in This Folder

### 📖 Documentation
- **`START-HERE.md`** - Quick start guide (read this first!)
- **`README-CUSTOMER-SIMULATION.md`** - Complete documentation
- **`README.md`** - This file

### 🛠️ Scripts (all executable)
1. **`manual-tag-subnets.sh`** - Tag subnets manually via AWS CLI
2. **`verify-manual-tags.sh`** - Verify tags are correctly applied
3. **`lock-subnet-tags.sh`** - Create IAM deny policy (makes tags immutable)
4. **`unlock-subnet-tags.sh`** - Remove IAM deny policy (restore normal access)
5. **`monitor-tag-errors.sh`** - Watch CloudTrail for tag AccessDenied errors
6. **`cleanup-manual-tags.sh`** - Remove all tags and IAM restrictions

## 🚀 Quick Start (from this folder)

```bash
# 1. Tag your subnets
./manual-tag-subnets.sh ../env/demo.tfvars

# 2. Verify tags
./verify-manual-tags.sh ../env/demo.tfvars

# 3. Lock tags (make immutable)
./lock-subnet-tags.sh ../env/demo.tfvars

# 4. Wait for IAM propagation
sleep 180

# 5. Run Terraform from parent directory
cd ..
terraform apply -var-file=env/demo.tfvars

# 6. Verify cluster
export KUBECONFIG=$(pwd)/installer-files/auth/kubeconfig
oc get nodes
oc get clusteroperators

# 7. Clean up when done
cd customer-tags-simulation
./cleanup-manual-tags.sh ../env/demo.tfvars
```

## 🚀 Quick Start (from parent directory)

```bash
# 1. Tag your subnets
./customer-tags-simulation/manual-tag-subnets.sh env/demo.tfvars

# 2. Verify tags
./customer-tags-simulation/verify-manual-tags.sh env/demo.tfvars

# 3. Lock tags (make immutable)
./customer-tags-simulation/lock-subnet-tags.sh env/demo.tfvars

# 4. Wait for IAM propagation
sleep 180

# 5. Run Terraform
terraform apply -var-file=env/demo.tfvars

# 6. Verify cluster
export KUBECONFIG=$(pwd)/installer-files/auth/kubeconfig
oc get nodes
oc get clusteroperators

# 7. Clean up when done
./customer-tags-simulation/cleanup-manual-tags.sh env/demo.tfvars
```

## 📊 What Gets Created (Outside Terraform)

### AWS Resources Created Manually:

1. **Subnet Tags** (via AWS CLI):
   - `kubernetes.io/cluster/<cluster-name>-<infra-id> = "shared"`
   - `kubernetes.io/role/internal-elb = "1"` (private subnets)
   - `kubernetes.io/role/elb = "1"` (public subnets)
   - Management tags (Environment, ManagedBy, etc.)

2. **IAM Policy** (via AWS CLI):
   - Policy Name: `<cluster-name>-deny-subnet-tags`
   - Effect: Deny `ec2:CreateTags` and `ec2:DeleteTags` on subnets
   - Attached to: Control plane and worker IAM roles

**Important:** These are NOT managed by Terraform and must be cleaned up manually using the provided scripts.

## ⚠️ Important Notes

1. **No Terraform Changes** - Your `.tf` files remain unchanged
2. **Manual Cleanup Required** - Use `cleanup-manual-tags.sh` when done
3. **IAM Propagation** - Wait 2-3 minutes after locking tags
4. **Outside Terraform State** - These resources won't appear in `terraform state`

## ✅ Expected Results

### Success
- ✅ OpenShift installation completes
- ✅ All cluster operators are healthy
- ⚠️ Some `AccessDenied` errors in logs (expected, bypassed)
- ✅ All operations work (scaling, load balancers)

### Failure
- ❌ Installation hangs or fails
- ❌ Operators become degraded
- ❌ Operations blocked by tag restrictions

If you see failures, you may need the custom OpenShift installer with tag bypass patches.

## 🧹 Cleanup

```bash
# From this folder
./cleanup-manual-tags.sh ../env/demo.tfvars

# Or from parent directory
./customer-tags-simulation/cleanup-manual-tags.sh env/demo.tfvars
```

This will:
- Remove IAM deny policies
- Remove all manually applied tags
- Restore environment to original state

## 📖 Full Documentation

See **`README-CUSTOMER-SIMULATION.md`** for:
- Detailed architecture explanation
- Troubleshooting guide
- Complete testing scenarios
- Expected outcomes

## 🆘 Quick Reference

| Command | Purpose |
|---------|---------|
| `./manual-tag-subnets.sh ../env/demo.tfvars` | Apply tags to subnets |
| `./verify-manual-tags.sh ../env/demo.tfvars` | Check tags are correct |
| `./lock-subnet-tags.sh ../env/demo.tfvars` | Make tags immutable |
| `./unlock-subnet-tags.sh ../env/demo.tfvars` | Remove restrictions |
| `./monitor-tag-errors.sh 30` | Watch for tag errors (30 min) |
| `./cleanup-manual-tags.sh ../env/demo.tfvars` | Full cleanup |

## 🎯 Workflow Diagram

```
customer-tags-simulation/
    ↓
1. manual-tag-subnets.sh      → Tag subnets
    ↓
2. verify-manual-tags.sh      → Verify tags
    ↓
3. lock-subnet-tags.sh        → Make immutable
    ↓
4. [Go to parent directory]
    ↓
5. terraform apply            → Test installation
    ↓
6. [Test cluster operations]
    ↓
7. customer-tags-simulation/
   cleanup-manual-tags.sh     → Clean up
```

## 💡 Tips

- Run scripts from this folder using relative paths: `./script.sh ../env/demo.tfvars`
- Or run from parent: `./customer-tags-simulation/script.sh env/demo.tfvars`
- All scripts accept the tfvars file path as first argument
- Use `monitor-tag-errors.sh` in a separate terminal during installation
- Keep terminal output for debugging if issues occur

## 🔗 Related Files

In parent directory:
- `env/demo.tfvars` - Your configuration
- `README.md` - Main OpenShift installation guide
- `env/VARIABLES-EXPLAINED.md` - Variables documentation

---

**Created:** January 2026  
**For:** OpenShift 4.16 on AWS  
**Purpose:** Customer environment simulation
