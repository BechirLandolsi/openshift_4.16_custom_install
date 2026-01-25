# 🚀 Customer Environment Simulation - Quick Start

## What Is This?

You want to test if your OpenShift installation works when subnet tags are **immutable** (read-only), simulating your customer's environment **WITHOUT modifying your Terraform code**.

## 3-Step Process (1-2 hours)

### ✅ Step 1: Tag Subnets Manually (5 min)

Simulate customer's pre-tagged environment:

```bash
# From this folder (customer-tags-simulation/)
./manual-tag-subnets.sh ../env/demo.tfvars
./verify-manual-tags.sh ../env/demo.tfvars

# OR from parent directory (terraform-openshift-v18/)
./customer-tags-simulation/manual-tag-subnets.sh env/demo.tfvars
./customer-tags-simulation/verify-manual-tags.sh env/demo.tfvars
```

### 🔒 Step 2: Lock Tags (5 min)

Make tags immutable via IAM deny policy:

```bash
# From this folder
./lock-subnet-tags.sh ../env/demo.tfvars

# OR from parent directory
./customer-tags-simulation/lock-subnet-tags.sh env/demo.tfvars

# Wait 2-3 minutes for IAM propagation
sleep 180
```

### 🎯 Step 3: Test Installation (30-45 min)

Run your **existing** Terraform (no changes needed):

```bash
# Must run from parent directory (terraform-openshift-v18/)
cd ..

# Optional: Monitor tag errors in another terminal
./customer-tags-simulation/monitor-tag-errors.sh 30

# Run Terraform normally
terraform apply -var-file=env/demo.tfvars

# Verify cluster
export KUBECONFIG=$(pwd)/installer-files/auth/kubeconfig
oc get nodes
oc get clusteroperators
```

## Expected Results

### ✅ Success

- Installation completes
- All cluster operators healthy
- Some `AccessDenied` logs (OK, bypassed)
- Operations work normally

**Conclusion:** Ready for customer deployment!

### ❌ Failure

- Installation fails/hangs
- Operators degraded
- Machines can't be created

**Action:** You may need the custom OpenShift installer with tag bypass patches (see main README)

## Cleanup

```bash
# From this folder
./cleanup-manual-tags.sh ../env/demo.tfvars

# OR from parent directory
./customer-tags-simulation/cleanup-manual-tags.sh env/demo.tfvars
```

## Files Overview

| Script | What It Does |
|--------|--------------|
| 📝 `manual-tag-subnets.sh` | Tag subnets manually (customer simulation) |
| ✓ `verify-manual-tags.sh` | Check tags are correct |
| 🔒 `lock-subnet-tags.sh` | Make tags immutable |
| 🔓 `unlock-subnet-tags.sh` | Remove restrictions |
| 👁 `monitor-tag-errors.sh` | Watch for tag denials |
| 🧹 `cleanup-manual-tags.sh` | Remove all changes |

## Full Documentation

📖 See [README-CUSTOMER-SIMULATION.md](./README-CUSTOMER-SIMULATION.md) for complete details

## Key Points

- ✅ **NO changes to your Terraform code**
- ✅ **Fully reversible**
- ✅ **Simulates exact customer environment**
- ⚠️ **IAM policies created outside Terraform** (must clean up manually)

## Your First Command

```bash
# From this folder (customer-tags-simulation/)
./manual-tag-subnets.sh ../env/demo.tfvars

# OR from parent directory (terraform-openshift-v18/)
./customer-tags-simulation/manual-tag-subnets.sh env/demo.tfvars
```

Good luck! 🎉
