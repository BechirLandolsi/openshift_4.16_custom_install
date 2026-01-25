# 🔗 Customer Environment Simulation

## Looking for the customer tag simulation tools?

All scripts and documentation for testing OpenShift with immutable subnet tags have been organized in:

📁 **`customer-tags-simulation/`**

## Quick Access

```bash
cd customer-tags-simulation/
cat START-HERE.md
```

## What's Inside?

The `customer-tags-simulation/` folder contains:

- **📖 Documentation** - Complete guides and quick starts
- **🛠️ 6 Scripts** - Tag subnets, lock tags, verify, monitor, cleanup
- **✅ Ready to Use** - All scripts are executable and tested

## Quick Start from Here

```bash
# 1. Tag subnets
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

# 7. Clean up
./customer-tags-simulation/cleanup-manual-tags.sh env/demo.tfvars
```

## Purpose

Test if your OpenShift installation works when:
- ✅ Subnets are pre-tagged with OpenShift-required tags
- ✅ IAM policies prevent tag modifications (immutable tags)
- ✅ Simulates restricted customer environment
- ✅ **NO changes to your Terraform code**

## Documentation

- **Quick Start:** `customer-tags-simulation/START-HERE.md`
- **Full Guide:** `customer-tags-simulation/README-CUSTOMER-SIMULATION.md`
- **This Folder:** `customer-tags-simulation/README.md`

## Key Benefits

1. **Zero Terraform Changes** - Your configuration remains untouched
2. **Fully Reversible** - Easy cleanup with provided scripts
3. **Real Simulation** - Exact customer restrictions
4. **Production Ready** - Proves it works before deployment

---

📂 Go to: [`customer-tags-simulation/`](./customer-tags-simulation/)
