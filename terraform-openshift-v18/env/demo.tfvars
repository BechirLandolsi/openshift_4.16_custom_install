account_id              = "XXXXXXXXXXXX"
region                  = "eu-west-3"
vpc_id                  = "vpc-XXXXXXXXXXXXXXXXX"
ccoe_boundary           = "arn:aws:iam::XXXXXXXXXXXX:policy/XXX-boundarie-iam-policy"
release_image           = "quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64"       #Change to: your-registry.company.com/ocp-release:4.16.9-x86_64 if you are in a disconnected environment
openshift_ssh_key       = ""
domain                      = "hp...fr"
ami                         = "ami-XXXXXXXXXXXXXXXXX"
service_network_cidr        = "XXX.XXX.0.0/16"
machine_network_cidr        = ["XXX.XXX.XXX.0/23"]
cluster_network_cidr        = "XXX.XXX.0.0/14"
cluster_network_host_prefix = "23"

aws_worker_iam_id             = "ami-XXXXXXXXXXXXXXXXX"
hosted_zone                   = "XXXXXXXXXXXXXXXXXXXXXX"


aws_worker_availability_zones = ["eu-west-3a","eu-west-3b","eu-west-3c"]
openshift_pull_secret         = "openshift/openshift_pull_secret.json"
openshift_installer_url       = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest"
aws_private_subnets           = ["subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX"]
aws_public_subnets            = ["subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX"]
route_default                 = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXXXXXXXXXX.elb.eu-west-1.amazonaws.com"
proxy_config                  = {
    enabled    = false
    httpProxy  = "http://proxy...fr:8080"
    httpsProxy = "http://proxy...fr:8080"
    noProxy    = "127.0.0.1,localhost,169.254.169.254,10.36.0.0,172.20.0.0,172.21.0.0,172.30.0.0,XXXXX.fr,ec2.eu-west-1.amazonaws.com,elasticloadbalancing.eu-west-1.amazonaws.com,s3.eu-west-1.amazonaws.com,.XXXXXXnetwork.com"
}

# ==============================================================================
# User-Defined Tags
# ==============================================================================
# These tags will be applied by OpenShift to ALL resources it creates:
# - EC2 instances (control plane, worker, infra nodes)
# - EBS volumes
# - Load balancers (NLB/ELB)
# - Security groups
# - Network interfaces
# - Any other AWS resources provisioned by OpenShift
#
# NOTE: These tags are NOT applied to pre-existing resources (VPC, subnets, etc.)
#       They only apply to resources created during cluster installation.
#
# Replace the example tags below with your organization's required tags.
# ==============================================================================

tags = {
    "tag1": "Value1",
    "tag2": "Value2",
    "tag3": "Value3",
    "tag4": "Value4",
    "tag5": "Value5",
    "tag6": "Value6",
    "tag7": "Value7",
    "tag8": "Value8"
}

# Example of real organizational tags (uncomment and modify as needed):
# tags = {
#     "Environment": "Production",
#     "Project": "OpenShift-Platform",
#     "CostCenter": "IT-Infrastructure",
#     "Owner": "platform-team@company.com",
#     "ManagedBy": "Terraform",
#     "Compliance": "ISO27001",
#     "BackupPolicy": "Daily",
#     "Department": "Engineering",
#     "Application": "Container-Platform",
#     "Criticality": "High"
# }


kms_ec2_alias = "alias/ec2-ebs"

#The Infra ID tagged on the subnets for the cluster
infra_random_id         = "demo-d44a5"
#Customized values OpenShift cluster "bkprestore"
s3_bucket_name_oidc     = "my-cluster-bkprestore"
cluster_name            = "my-ocp-cluster"
control_plane_role_name = "ocpcontrolplane-iam-role"
aws_iam_role_compute_node = "ocpcontrolplane-iam-role"
ocpcontrolplane_policy = "ocpcontrolplane-policy-iam-policy"
aws_worker_iam_role           = "ocpworkernode-iam-role"
ocpworkernode_policy = "ocpworkernode-policy-iam-policy"

# ==============================================================================
# Node Sizing & Capacity (Adjust based on workload requirements)
# ==============================================================================

# ------------------------------------------------------------------------------
# Worker Nodes (Application workloads)
# ------------------------------------------------------------------------------
# Total number of worker nodes across all AZs
# Minimum: 2 (for HA), Recommended: 3+
worker_count = 3

# EC2 instance type for worker nodes
# Options: m5.xlarge, m5.2xlarge, c5.2xlarge, c5.4xlarge, etc.
# Choose based on CPU/Memory requirements
aws_worker_instance_type = "m5.2xlarge"

# Root volume type for worker nodes
# Options: gp3 (general purpose), io1/io2 (high performance)
aws_worker_root_volume_type = "gp3"

# Root volume size in GB
# Minimum: 120GB, Recommended: 200-300GB
aws_worker_root_volume_size = "200"

# IOPS for io1/io2 volumes (ignored for gp3)
# Only needed if using io1 or io2
aws_worker_root_volume_iops = "3000"

# ------------------------------------------------------------------------------
# Infrastructure Nodes (OpenShift internal services - Optional, for Day 2)
# ------------------------------------------------------------------------------
# Number of infra nodes per availability zone
# Infra nodes run: ingress router, monitoring, logging, registry
# Set to "0" to skip infra nodes and run on workers
# Set to "1" for dedicated infra nodes (recommended for production)
aws_infra_count_per_availability_zone = "1"

# EC2 instance type for infra nodes
aws_infra_instance_type = "m5.xlarge"

# Infra node storage configuration
aws_infra_root_volume_type = "gp3"
aws_infra_root_volume_size = "200"
aws_infra_root_volume_iops = "3000"

# ------------------------------------------------------------------------------
# Control Plane / Master Nodes (Always 3 for HA)
# ------------------------------------------------------------------------------
# Number of control plane nodes (DO NOT CHANGE - must be 3 for HA)
master_count = 3

# EC2 instance type for control plane
# Minimum: m5.xlarge, Recommended: m5.2xlarge or larger
aws_master_instance_type = "m5.2xlarge"

# Control plane storage configuration
# Needs good IOPS for etcd database
aws_master_volume_type = "gp3"
aws_master_volume_size = "200"

# IOPS for master volumes (important for etcd performance)
# gp3: 3000-16000, io1: up to 64000
aws_master_volume_iops = "4000"


