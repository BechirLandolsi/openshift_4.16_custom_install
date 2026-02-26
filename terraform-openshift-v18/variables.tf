variable "region" {
  type        = string
  //default     = "eu-west-1"
  description = "The AWS region"
}

variable "tfvars_file" {
  type        = string
  description = "Path to the tfvars file (used by destroy script)"
}

variable "tags" {
  type = map(string)
  description = "The tag you want to add"
}

variable "vpc_id" {
  type        = string
  description = "The VPC id"
 
}

variable "s3_bucket_name_oidc" {
  type        = string
  description = "The name of the S3 bucket for OIDC provider"
}

variable "ccoe_boundary" {
  type        = string
  description = "The CCOE boundary we have to use"
}

variable "cluster_name" {
  type        = string
  description = "The name of the OpenShift cluster"
}

variable "infra_random_id" {
  type    = string
  description = "The infra ID that is tagged on the subnets where the OpenShift cluster will be installed"
  #default = "b56bx"
}

variable "account_id" {
  type        = string
  description = "AWS account ID (12 digits)"
}

variable "control_plane_role_name" {
  type        = string
  #default     = "ocpcontrolplane"
  description = "The name of the oc control plane role"
}

variable "release_image" {
  type        = string
  #default     = "quay.io/openshift-release-dev/ocp-release:4.12.30-x86_64"
}

########################################################
###############   TEMPLATE VARIABLES   #################
########################################################

variable "domain" {
  type        = string
  description = "The DNS domain for the cluster (e.g., example.com)"
}

variable "ami" {
  type        = string
  description = "The AMI ID for the RHCOS nodes (KMS-encrypted)"
}

variable "service_network_cidr" {
  type        = string
  #default     = "172.30.0.0/16"
}

variable "machine_network_cidr" {
  type        = list(string)
  description = "The IP address blocks for machines (your VPC CIDR)"
}

variable "cluster_network_cidr" {
  type        = string
  description = "The IP address blocks for pods (default: 10.128.0.0/14)"
}

variable "cluster_network_host_prefix" {
  type        = string
  #default     = "23"
}

variable "aws_master_volume_type" {
  type        = string
  description = "The type of volume for the root block device of master nodes."
  #default     = "io1"
}

variable "aws_master_volume_size" {
  type        = string
  description = "The size of the volume in gigabytes for the root block device of master nodes."
  #default     = "500"
}

variable "aws_master_volume_iops" {
  type        = string
  description = "The amount of provisioned IOPS for the root block device of master nodes. Ignored if the volume type is not io1."
  #default     = "4000"
}

## COMPUTE RELATED

variable "aws_iam_role_compute_node" {
  type        = string
  description = "The IAM role for compute node"
  #default     = "ocpcontrolplane"
}

variable "master_count" {
  type        = number
  description = "The number of master nodes."
  #default     = 3
}

variable "aws_master_instance_type" {
  type        = string
  description = "Instance type for the master node(s). Example: `m4.large`."
  #default     = "m5.xlarge"
}

##########################
########### WORKER RELATED
##########################


variable "aws_worker_iam_role" {
  type        = string
  description = "The IAM role for worker node"
  #default     = "ocpworkernode"
}

variable "aws_worker_iam_id" {
  type        = string
  description = "The AMI ID for worker nodes (same as master AMI)"
}

variable "hosted_zone" {
  type        = string
  description = "The Route53 Hosted Zone ID"
}

variable "aws_worker_instance_type" {
  type        = string
  description = "Instance type for the worker node(s). Example: `m4.large`."
  #default     = "c5.4xlarge"
}

variable "aws_worker_root_volume_type" {
  type        = string
  description = "The type of volume for the root block device of worker nodes."
  #default     = "io1"
}

variable "aws_worker_root_volume_size" {
  type        = string
  description = "The size of the volume in gigabytes for the root block device of worker nodes."
  #default     = "500"
}

variable "aws_worker_root_volume_iops" {
  type        = string
  description = "The amount of provisioned IOPS for the root block device of worker nodes. Ignored if the volume type is not io1."
  #default     = "2000"
}

variable "worker_count" {
  type        = number
  description = "The number of worker nodes."
  #default     = 3
}

variable "aws_worker_availability_zones" {
  type        = list(string)
  description = "The availability zones to provision for workers. Worker instances are created by the machine-API operator, but this variable controls their supporting infrastructure (subnets, routing, etc.)."
  #default     = ["eu-west-1a","eu-west-1b","eu-west-1c"]
}

variable "openshift_pull_secret" {
  type        = string
  #default     = "openshift_pull_secret.json"
}

variable "openshift_installer_url" {
  type        = string
  description = "The URL to download OpenShift installer."
  #default     = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest"
}

variable "aws_private_subnets" {
  type        = list(string)
  description = "The private subnets for nodes (masters and workers)"
}

variable "aws_public_subnets" {
  type = list(string)
  description = "The public subnets where NAT Gateways are located. Required even for Internal clusters."
  default     = []
}

variable "openshift_ssh_key" {
  type    = string
  default = ""
}

variable "proxy_config" {
  type        = map(string)
  description = "Proxy configuration for the cluster (set in tfvars)"
  # Example configuration (set actual values in your tfvars file):
  # proxy_config = {
  #   enabled    = "true"
  #   httpProxy  = "http://your-proxy.example.com:8080"
  #   httpsProxy = "http://your-proxy.example.com:8080"
  #   noProxy    = "127.0.0.1,localhost,169.254.169.254,.your-domain.com"
  # }
}

variable "route_default" {
  type        = string
  description = "The DNSName redirection (NLB DNS name)"
}


variable "ocpcontrolplane_policy" {
  type        = string
  description = "ocpcontrolplane policy Name"
  #default = "ocpcontrolplane-policy"
}


variable "ocpworkernode_policy" {
  type        = string
  description = "ocpworkernode_policy policy Name"
}

variable "kms_ec2_alias" {
  type = string
  description = "KMS master key to encrypt ec2 EBS volumes"
}

variable "kms_additional_role_arns" {
  type        = list(string)
  description = "Additional IAM role ARNs to include in KMS key policy (e.g., CSI driver role)"
  default     = []
}


##########################
########### INFRA RELATED
##########################

variable "aws_infra_root_volume_type" {
  type        = string
  description = "The type of volume for the root block device of infra nodes."
  #default     = "io1"
}

variable "aws_infra_root_volume_size" {
  type        = string
  description = "The size of the volume in gigabytes for the root block device of infra nodes."
  #default     = "500"
}

variable "aws_infra_root_volume_iops" {
  type        = string
  description = "The amount of provisioned IOPS for the root block device of infra nodes. Ignored if the volume type is not io1."
  #default     = "4000"
}

variable "aws_infra_instance_type" {
  type        = string
  description = "Instance type for the infra node(s). Example: `m4.large`."
  #default     = "c5.4xlarge"
}

variable "aws_infra_count_per_availability_zone" {
  type        = string
  description = "The number of the infra nodes replicas for each availability zone"
  #default     = "500"
}
