# Customer Environment Simulation - Immutable Subnet Tags

## Overview

This guide helps you simulate your customer's environment where:
- Subnets are **pre-tagged** with OpenShift-required tags
- Subnet tags are **immutable** (cannot be modified)
- OpenShift installation must **bypass tag errors** and work anyway

**IMPORTANT:** This approach does **NOT modify your Terraform configuration**. All tagging and restrictions are done manually outside of Terraform to simulate the customer's pre-existing environment.

## Why This Approach?

Your customer has:
1. Pre-existing VPC and subnets with tags already applied
2. Security policies that prevent applications (including OpenShift) from modifying subnet tags
3. A need to ensure OpenShift works in this restricted environment

This simulation lets you test your installation in an identical environment **before** deploying to the customer.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Manual Tagging (Simulates Customer's Pre-Tagged Env)   │
├─────────────────────────────────────────────────────────────────┤
│ You manually tag subnets with:                                  │
│   • kubernetes.io/cluster/<cluster-id> = "shared"               │
│   • kubernetes.io/role/internal-elb = "1" (private)            │
│   • kubernetes.io/role/elb = "1" (public)                      │
│                                                                  │
│ This is done via AWS CLI, NOT Terraform                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Lock Tags (Simulates Customer's Security Policy)       │
├─────────────────────────────────────────────────────────────────┤
│ Create IAM deny policy (outside Terraform) that prevents:      │
│   • ec2:CreateTags on subnets                                  │
│   • ec2:DeleteTags on subnets                                  │
│                                                                  │
│ Applied to OpenShift IAM roles to enforce restrictions          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Run Your Existing Terraform (NO CHANGES NEEDED)        │
├─────────────────────────────────────────────────────────────────┤
│ Run: terraform apply -var-file=env/demo.tfvars                 │
│                                                                  │
│ OpenShift installer should:                                     │
│   ✓ Detect pre-existing tags                                   │
│   ✓ Bypass AccessDenied errors when trying to tag              │
│   ✓ Complete installation successfully                         │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start (30-45 minutes)

### Prerequisites

✅ AWS CLI configured with appropriate credentials  
✅ Your `env/demo.tfvars` file is ready  
✅ VPC and subnets already exist in AWS  
✅ IAM roles for OpenShift already exist (or will be created by Terraform)

### Step 1: Tag Subnets Manually (5 minutes)

```bash
cd /path/to/terraform-openshift-v18

# Tag all subnets with OpenShift-required tags
./manual-tag-subnets.sh env/demo.tfvars
```

**What this does:**
- Reads your subnet IDs from `demo.tfvars`
- Applies OpenShift cluster tag: `kubernetes.io/cluster/my-ocp-cluster-demo-d44a5=shared`
- Adds ELB role tags for load balancer functionality
- Tags are applied via AWS CLI, **not Terraform**

**Verify tags were applied:**

```bash
./verify-manual-tags.sh env/demo.tfvars
```

Expected output:
```
✓ Required cluster tag found
✓ ELB role tag found
✓ Internal ELB role tag found
```

### Step 2: Lock Subnet Tags (5 minutes)

```bash
# Make subnet tags immutable
./lock-subnet-tags.sh env/demo.tfvars
```

**What this does:**
- Creates IAM policy `my-ocp-cluster-deny-subnet-tags` (outside Terraform)
- Denies `ec2:CreateTags` and `ec2:DeleteTags` on your subnets
- Attaches policy to OpenShift control plane and worker IAM roles
- OpenShift will now get `AccessDenied` when trying to tag subnets

**Wait 2-3 minutes for IAM policy propagation.**

### Step 3: Monitor Tag Errors (Optional)

In a separate terminal, start monitoring for tag-related errors:

```bash
# Monitor CloudTrail for tag denials (runs for 30 minutes)
./monitor-tag-errors.sh 30
```

This will show you when OpenShift tries to tag subnets and gets denied.

### Step 4: Run Terraform (30-45 minutes)

```bash
# Run your existing Terraform WITHOUT any modifications
terraform apply -var-file=env/demo.tfvars
```

**Watch for:**
- ✅ Installation completes successfully
- ⚠️ Some `AccessDenied` errors in logs (expected, should be bypassed)
- ✅ Cluster becomes operational

### Step 5: Verify Cluster Health (5 minutes)

```bash
export KUBECONFIG=$(pwd)/installer-files/auth/kubeconfig

# Check all nodes
oc get nodes

# Check cluster operators
oc get clusteroperators

# Look for degraded operators
oc get co -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Degraded" and .status=="True")) | .metadata.name'
```

**Expected Results:**
- ✅ All nodes are Ready
- ✅ All cluster operators are Available
- ✅ No operators are Degraded
- ⚠️ Some AccessDenied logs are OK (cosmetic)

### Step 6: Test Cluster Operations (15 minutes)

Test that operations work with immutable tags:

#### Test 1: Scale Workers

```bash
# Scale a worker machineset
MACHINESET=$(oc get machinesets -n openshift-machine-api -o name | head -1)
oc scale $MACHINESET --replicas=4 -n openshift-machine-api

# Wait for new node
watch oc get machines -n openshift-machine-api
oc get nodes
```

**Expected:** ✅ New worker node joins successfully

#### Test 2: Create Load Balancer

```bash
# Create test service
oc new-project test-immutable-tags
oc create deployment nginx --image=nginx
oc expose deployment nginx --type=LoadBalancer --port=80

# Check LB creation
oc get svc nginx -w
```

**Expected:** ✅ LoadBalancer gets external IP/hostname

#### Test 3: Check Logs for Tag Errors

```bash
# Check machine-api-operator
oc logs -n openshift-machine-api-operator deployment/machine-api-operator --tail=100 | grep -i tag

# Check AWS cloud provider
oc logs -n openshift-cloud-controller-manager daemonset/aws-cloud-controller-manager --tail=100 | grep -i tag
```

**Expected:** ⚠️ You may see AccessDenied errors, but operations should complete

## Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `manual-tag-subnets.sh` | Tag subnets manually (simulates customer env) | `./manual-tag-subnets.sh env/demo.tfvars` |
| `verify-manual-tags.sh` | Verify tags were applied correctly | `./verify-manual-tags.sh env/demo.tfvars` |
| `lock-subnet-tags.sh` | Make tags immutable via IAM deny policy | `./lock-subnet-tags.sh env/demo.tfvars` |
| `unlock-subnet-tags.sh` | Remove IAM restrictions | `./unlock-subnet-tags.sh env/demo.tfvars` |
| `monitor-tag-errors.sh` | Watch CloudTrail for tag denials | `./monitor-tag-errors.sh 30` |
| `cleanup-manual-tags.sh` | Remove all tags and restrictions | `./cleanup-manual-tags.sh env/demo.tfvars` |

## What Gets Created (Outside Terraform)

### IAM Policy

**Name:** `<cluster-name>-deny-subnet-tags`  
**Effect:** Deny  
**Actions:** `ec2:CreateTags`, `ec2:DeleteTags`  
**Resources:** Your subnet ARNs  
**Attached To:** Control plane and worker IAM roles

### Subnet Tags

Applied to each subnet:
```
kubernetes.io/cluster/<cluster-name>-<infra-id> = "shared"
kubernetes.io/role/internal-elb = "1" (private subnets)
kubernetes.io/role/elb = "1" (public subnets)
Name = "<cluster-name>-<infra-id>-subnet"
Environment = "OpenShift"
ManagedBy = "Manual"
TagProtection = "Simulated"
```

## Expected Test Outcomes

### ✅ Success: Installation Works with Immutable Tags

**Indicators:**
- Terraform completes without fatal errors
- All cluster operators become Available
- Nodes join the cluster successfully
- Load balancers can be created
- Some AccessDenied logs exist but don't block operations

**Conclusion:** Your OpenShift installer correctly handles immutable subnet tags. Ready for customer deployment!

### ⚠️ Partial Success: Cosmetic Errors Only

**Indicators:**
- Installation completes
- All operations work
- Lots of AccessDenied errors in logs
- No degraded operators

**Conclusion:** Acceptable. Document expected errors for customer.

### ❌ Failure: Operations Blocked

**Indicators:**
- Installation fails or hangs
- Cluster operators become Degraded
- Machines cannot be created
- Load balancers fail to provision

**Action Required:**
1. Check if you're using the custom OpenShift installer with tag bypass patches
2. Review the README note about custom installer requirements
3. May need to apply installer modifications mentioned in main README

## Cleanup & Restore

### Remove Restrictions Only (Keep Cluster)

```bash
# Unlock tags but keep cluster running
./unlock-subnet-tags.sh env/demo.tfvars
```

### Full Cleanup (Destroy Everything)

```bash
# 1. Destroy OpenShift cluster
./delete-cluster.sh

# 2. Remove tags and IAM policies
./cleanup-manual-tags.sh env/demo.tfvars
```

## Troubleshooting

### Issue: Tags not applied

**Check:**
```bash
./verify-manual-tags.sh env/demo.tfvars
```

**Fix:**
```bash
./manual-tag-subnets.sh env/demo.tfvars
```

### Issue: IAM policy already exists

**Symptom:** `EntityAlreadyExists` error when running `lock-subnet-tags.sh`

**Fix:** Script handles this automatically. The existing policy will be used.

### Issue: Installation fails with "AccessDenied"

**Check:** Are you using the custom OpenShift installer mentioned in the main README?

**Details:** The standard OpenShift installer may require subnet tag write access. The custom installer with tag bypass patches handles this gracefully.

### Issue: Can't remove IAM policy

**Symptom:** `NoSuchEntity` error when unlocking

**Check:**
```bash
aws iam list-policies --scope Local | grep deny-subnet-tags
```

**Fix:** Policy may have already been removed. Safe to ignore.

### Issue: Monitor script shows no errors

**This is actually good!** It means either:
1. OpenShift isn't trying to tag subnets (tags already exist)
2. IAM policies haven't propagated yet (wait 2-3 minutes)

## Important Notes

### ⚠️ This Does NOT Modify Your Terraform

- ✅ Your `.tf` files remain unchanged
- ✅ Your `demo.tfvars` remains unchanged
- ✅ All changes are made via AWS CLI
- ✅ Terraform state is not affected by manual tagging

### ⚠️ IAM Policies Are Created Outside Terraform

- ⚠️ IAM deny policies are not managed by Terraform
- ⚠️ You must manually remove them with `unlock-subnet-tags.sh`
- ⚠️ They won't be cleaned up by `terraform destroy`

### ⚠️ Custom Installer May Be Required

Check your main README for notes about the custom OpenShift installer with tag bypass modifications. The standard installer may not handle immutable subnet tags gracefully.

## Customer Deployment Checklist

After successful testing:

- [ ] Installation completed with immutable tags
- [ ] All cluster operators are healthy
- [ ] Worker scaling works
- [ ] Load balancers can be created
- [ ] Documented any expected AccessDenied errors
- [ ] Tested with customer's actual tag values
- [ ] Verified IAM policies match customer's restrictions
- [ ] Prepared runbook for customer deployment

## References

- Main README: [README.md](./README.md)
- Variables Guide: [env/VARIABLES-EXPLAINED.md](./env/VARIABLES-EXPLAINED.md)
- OpenShift on AWS: https://docs.openshift.com/container-platform/4.16/installing/installing_aws/

## Time Estimates

- Manual tagging: 5 minutes
- Lock tags: 5 minutes  
- Terraform apply: 30-45 minutes
- Verification: 5 minutes
- Testing operations: 15 minutes
- **Total: ~1-1.5 hours**

## Support

If you encounter issues:

1. Check `./monitor-tag-errors.sh` output for specific denied operations
2. Review CloudTrail for detailed error messages
3. Verify tags with `./verify-manual-tags.sh`
4. Check if custom installer is required (see main README)

---

**Created for:** Customer environment simulation  
**Compatible with:** OpenShift 4.16 on AWS  
**Approach:** Non-invasive, fully reversible
