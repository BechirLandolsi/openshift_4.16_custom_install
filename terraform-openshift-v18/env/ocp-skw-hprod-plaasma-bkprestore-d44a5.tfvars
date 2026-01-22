account_id              = "XXXXXXXXXXXX"
region                  = "eu-west-1"
vpc_id                  = "vpc-XXXXXXXXXXXXXXXXX"
ccoe_boundary           = "arn:aws:iam::XXXXXXXXXXXX:policy/XXX-boundarie-iam-policy"
release_image           = "quay.io/openshift-release-dev/ocp-release:4.14.21-x86_64"
openshift_ssh_key       = ""
domain                      = "hp...fr"
ami                         = "ami-XXXXXXXXXXXXXXXXX"
service_network_cidr        = "XXX.XXX.0.0/16"
machine_network_cidr        = ["XXX.XXX.XXX.0/23"]
cluster_network_cidr        = "XXX.XXX.0.0/14"
cluster_network_host_prefix = "23"

aws_worker_iam_id             = "ami-XXXXXXXXXXXXXXXXX"
hosted_zone                   = "XXXXXXXXXXXXXXXXXXXXXX"


aws_worker_availability_zones = ["eu-west-1a","eu-west-1b","eu-west-1c"]
openshift_pull_secret         = "openshift/openshift_pull_secret.json"
openshift_installer_url       = "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest"
aws_private_subnets           = ["subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX","subnet-XXXXXXXXXXXXXXXXX"]
route_default                 = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-XXXXXXXXXXXXXXXXX.elb.eu-west-1.amazonaws.com"
proxy_config                  = {
    enabled    = true
    httpProxy  = "http://proxy...fr:8080"
    httpsProxy = "http://proxy...fr:8080"
    noProxy    = "127.0.0.1,localhost,169.254.169.254,10.36.0.0,172.20.0.0,172.21.0.0,172.30.0.0,XXXXX.fr,ec2.eu-west-1.amazonaws.com,elasticloadbalancing.eu-west-1.amazonaws.com,s3.eu-west-1.amazonaws.com,.XXXXXXnetwork.com"
}

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


kms_ec2_alias = "alias/plaasma-ec2-cmk"

#The Infra ID tagged on the subnets for the cluster
infra_random_id         = "d44a5"
#Customized values OpenShift cluster "bkprestore"
s3_bucket_name_oidc     = "ocp-skw-hprod-oidc-plaasma-bkprestore"
cluster_name            = "bkprestore"
bucket_state_file       = "openshift-bkprestore"
control_plane_role_name = "ocpcontrolplane-bkprestore-iam-role"
aws_iam_role_compute_node = "ocpcontrolplane-bkprestore-iam-role"
ocpcontrolplane_policy = "ocpcontrolplane-policy-bkprestore-iam-policy"
aws_worker_iam_role           = "ocpworkernode-bkprestore-iam-role"
ocpworkernode_policy = "ocpworkernode-policy-bkprestore-iam-policy"



#Sizing
#worker nodes related
worker_count = 5
aws_worker_instance_type      = "c5.4xlarge"
aws_worker_root_volume_type   = "io1"
aws_worker_root_volume_size   = "300"
aws_worker_root_volume_iops   = "2000"

#infra nodes related
aws_infra_count_per_availability_zone = "1"
aws_infra_instance_type      = "c5.2xlarge"
aws_infra_root_volume_type   = "io1"
aws_infra_root_volume_size   = "300"
aws_infra_root_volume_iops   = "2000"

#master nodes related
master_count              = 3
aws_master_instance_type  = "m5.2xlarge"
aws_master_volume_type      = "io1"
aws_master_volume_size      = "300"
aws_master_volume_iops      = "4000"


