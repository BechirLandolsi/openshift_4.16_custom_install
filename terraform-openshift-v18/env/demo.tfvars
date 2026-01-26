# ==============================================================================
# OpenShift 4.16 Terraform Configuration
# ==============================================================================
# INSTRUCTIONS: Copy this file and replace all placeholder values with your
# actual AWS account and cluster configuration.
#
# Placeholders to replace:
#   - XXXXXXXXXXXX     -> Your 12-digit AWS Account ID
#   - vpc-XXXXXXXXX    -> Your VPC ID
#   - subnet-XXXXXXXXX -> Your Subnet IDs
#   - ami-XXXXXXXXX    -> Your AMI ID (pre-encrypted with KMS)
#   - your-domain.com  -> Your DNS domain
#   - ZXXXXXXXXXX      -> Your Route53 Hosted Zone ID
# ==============================================================================

# ==============================================================================
# AWS Account & Region Configuration
# ==============================================================================
account_id = "XXXXXXXXXXXX"
region     = "eu-west-3"
vpc_id     = "vpc-XXXXXXXXXXXXXXXXX"

# IAM Permission Boundary (optional - leave empty if not required)
# Some organizations require permission boundaries for IAM role creation
ccoe_boundary = ""
# Example: ccoe_boundary = "arn:aws:iam::XXXXXXXXXXXX:policy/your-boundary-policy"

# ==============================================================================
# OpenShift Release Configuration
# ==============================================================================
# Release image - use default for connected environments
# For disconnected: change to your-registry.company.com/ocp-release:4.16.9-x86_64
release_image = "quay.io/openshift-release-dev/ocp-release:4.16.9-x86_64"

# OpenShift installer download URL
openshift_installer_url = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest"

# Pull secret file path (download from console.redhat.com)
openshift_pull_secret = "openshift/openshift_pull_secret.json"

# ==============================================================================
# Cluster Identity
# ==============================================================================
# Cluster name - used for resource naming and DNS
cluster_name = "my-ocp-cluster"

# Infra random ID - must match the tag on your subnets
# Format: <prefix>-<random5chars> (e.g., "demo-a1b2c")
# This creates the full InfraID: my-ocp-cluster-a1b2c
infra_random_id = "demo-XXXXX"

# S3 bucket name for OIDC provider
s3_bucket_name_oidc = "my-cluster-oidc-bucket"

# ==============================================================================
# DNS Configuration
# ==============================================================================
# Base domain for the cluster (e.g., example.com)
# Cluster will be accessible at: api.my-ocp-cluster.example.com
domain = "your-domain.com"

# Route53 Hosted Zone ID for the domain
hosted_zone = "ZXXXXXXXXXXXXXXXXX"

# ==============================================================================
# Network Configuration
# ==============================================================================
# Private subnets (one per AZ, minimum 3 for HA)
aws_private_subnets = [
  "subnet-XXXXXXXXXXXXXXXXX",
  "subnet-XXXXXXXXXXXXXXXXX",
  "subnet-XXXXXXXXXXXXXXXXX"
]

# Public subnets (optional - for public-facing load balancers)
aws_public_subnets = [
  "subnet-XXXXXXXXXXXXXXXXX",
  "subnet-XXXXXXXXXXXXXXXXX",
  "subnet-XXXXXXXXXXXXXXXXX"
]

# Availability zones
aws_worker_availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]

# Network CIDRs
service_network_cidr        = "172.30.0.0/16"
cluster_network_cidr        = "10.128.0.0/14"
cluster_network_host_prefix = "23"
machine_network_cidr        = ["10.0.0.0/16"]

# Default route (optional - for egress)
route_default = ""

# ==============================================================================
# Proxy Configuration (for disconnected environments)
# ==============================================================================
proxy_config = {
  enabled    = false
  httpProxy  = ""
  httpsProxy = ""
  noProxy    = ""
}
# Example for disconnected:
# proxy_config = {
#   enabled    = true
#   httpProxy  = "http://proxy.company.com:8080"
#   httpsProxy = "http://proxy.company.com:8080"
#   noProxy    = "127.0.0.1,localhost,169.254.169.254,.company.com,.svc,.cluster.local"
# }

# ==============================================================================
# Custom AMI Configuration
# ==============================================================================
# IMPORTANT: AMI must be pre-encrypted with your KMS key!
# Use the scripts in custom-ami-build/ to create an encrypted AMI
ami               = "ami-XXXXXXXXXXXXXXXXX"
aws_worker_iam_id = "ami-XXXXXXXXXXXXXXXXX"

# SSH public key for cluster access (leave empty to auto-generate)
openshift_ssh_key = ""

# ==============================================================================
# KMS Configuration for EBS Encryption
# ==============================================================================
# KMS key alias for EBS encryption (must exist before terraform apply)
# Create using: custom-ami-build/create-kms-key.sh
kms_ec2_alias = "alias/openshift-ebs-encryption"

# Additional IAM role ARNs to include in KMS key policy
# These are created by ccoctl during installation
# Pattern: <CLUSTER_NAME>-openshift-<operator>-<credentials>
kms_additional_role_arns = [
  "arn:aws:iam::XXXXXXXXXXXX:role/CLUSTER_NAME-openshift-machine-api-aws-cloud-credentials",
  "arn:aws:iam::XXXXXXXXXXXX:role/CLUSTER_NAME-openshift-cluster-csi-drivers-ebs-cloud-credentia"
]

# ==============================================================================
# IAM Role Configuration
# ==============================================================================
# Names for Terraform-created IAM roles and policies
control_plane_role_name   = "ocp-controlplane-role"
aws_iam_role_compute_node = "ocp-controlplane-role"
ocpcontrolplane_policy    = "ocp-controlplane-policy"
aws_worker_iam_role       = "ocp-worker-role"
ocpworkernode_policy      = "ocp-worker-policy"

# ==============================================================================
# User-Defined Tags
# ==============================================================================
# Tags applied to ALL resources created by OpenShift
# Replace with your organization's required tags
tags = {
  "Environment" = "Production"
  "Project"     = "OpenShift-Platform"
  "CostCenter"  = "IT-Infrastructure"
  "Owner"       = "platform-team@company.com"
  "ManagedBy"   = "Terraform"
  "Compliance"  = "Required"
}

# ==============================================================================
# Control Plane Nodes (Masters)
# ==============================================================================
# Number of control plane nodes (DO NOT CHANGE - must be 3 for HA)
master_count = 3

# Instance type for control plane
aws_master_instance_type = "m5.2xlarge"

# Storage configuration
aws_master_volume_type = "gp3"
aws_master_volume_size = "200"
aws_master_volume_iops = "4000"

# ==============================================================================
# Worker Nodes
# ==============================================================================
# Number of worker nodes
worker_count = 3

# Instance type for workers
aws_worker_instance_type = "m5.2xlarge"

# Storage configuration
aws_worker_root_volume_type = "gp3"
aws_worker_root_volume_size = "200"
aws_worker_root_volume_iops = "3000"

# ==============================================================================
# Infrastructure Nodes (Optional)
# ==============================================================================
# Number of infra nodes per AZ (0 = disable, 1 = recommended for production)
aws_infra_count_per_availability_zone = "1"

# Instance type for infra nodes
aws_infra_instance_type = "m5.xlarge"

# Storage configuration
aws_infra_root_volume_type = "gp3"
aws_infra_root_volume_size = "200"
aws_infra_root_volume_iops = "3000"
