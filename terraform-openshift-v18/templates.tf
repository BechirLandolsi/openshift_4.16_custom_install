data "aws_kms_alias" "ec2_cmk_arn" {
  name = var.kms_ec2_alias
}
data "template_file" "install_config_yaml" {
  template = <<-EOF
apiVersion: v1
baseDomain: ${var.domain}
credentialsMode: Manual
controlPlane:
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      amiID: ${var.ami}
      iamRole: ${var.control_plane_role_name}
      zones: %{ for zone in var.aws_worker_availability_zones}
      - ${zone}%{ endfor }
      rootVolume:
        iops: ${var.aws_master_volume_iops}
        size: ${var.aws_master_volume_size}
        type: ${var.aws_master_volume_type}
        # kmsKeyARN not needed - AMI is already encrypted with the CMK
      type: ${var.aws_master_instance_type}
      metadataService:
        authentication: Required
  replicas: ${var.master_count}

compute:
- hyperthreading: Enabled
  name: worker
  platform:
    aws:
      amiID: ${var.aws_worker_iam_id}
      iamRole: ${var.aws_worker_iam_role}
      zones: %{ for zone in var.aws_worker_availability_zones}
      - ${zone}%{ endfor }
      rootVolume:
        iops: ${var.aws_worker_root_volume_iops}
        size: ${var.aws_worker_root_volume_size}
        type: ${var.aws_worker_root_volume_type}
        # kmsKeyARN not needed - AMI is already encrypted with the CMK
      type: ${var.aws_worker_instance_type}
      metadataService:
        authentication: Required
  replicas: ${var.worker_count}

metadata:
  name: ${var.cluster_name}

platform:
  aws:
    region: ${var.region}
    amiID: ${var.ami}
    hostedZone: ${var.hosted_zone}
    subnets: %{ for subnet in var.aws_private_subnets}
    - ${subnet}%{ endfor }%{ if length(var.aws_public_subnets) > 0}%{ for subnet in var.aws_public_subnets}
    - ${subnet}%{ endfor }%{ endif }
    lbType: NLB
    userTags: %{ for key, value in var.tags}
      "${key}": ${value} %{ endfor }
    propagateUserTags: true
fips: false 
publish: Internal

networking:
  clusterNetworks:
  - cidr: ${var.cluster_network_cidr}
    hostPrefix: ${var.cluster_network_host_prefix}
  machineNetwork: %{ for cidr in var.machine_network_cidr}
  - cidr: ${cidr}%{ endfor }
  networkType: OVNKubernetes
  serviceNetwork:
  - ${var.service_network_cidr}

pullSecret: '${file("${var.openshift_pull_secret}")}'

sshKey: '${local.public_ssh_key}'
%{if var.proxy_config["enabled"]}proxy:
  httpProxy: ${var.proxy_config["httpProxy"]}
  httpsProxy: ${var.proxy_config["httpsProxy"]}
  noProxy: ${var.proxy_config["noProxy"]},${var.domain}%{endif}
EOF
}

resource "local_file" "install_config" {
  content  =  data.template_file.install_config_yaml.rendered
  filename =  "installer-files/install-config.yaml"
}

data "template_file" "cluster_ingress" {
  template = <<-EOF
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  creationTimestamp: null
  name: default
  namespace: openshift-ingress-operator
spec:
  clientTLS:
    clientCA:
      name: ""
    clientCertificatePolicy: ""
  endpointPublishingStrategy:
    loadBalancer:
      scope: Internal
      dnsManagementPolicy: Unmanaged
      providerParameters:
        aws:
          networkLoadBalancer: {}
          type: NLB
        type: AWS
    type: LoadBalancerService
  httpCompression: {}
  httpErrorCodePages:
    name: ""
  tuningOptions:
    reloadInterval: 0s
  unsupportedConfigOverrides: null
status:
  availableReplicas: 0
  domain: ""
  selector: ""
EOF
}


data "aws_subnet" "subnets" {
  for_each = toset(var.aws_worker_availability_zones)

  filter {
    name   = "availability-zone"
    values = [each.key]
  }

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["ocp"]
  }
}


data "template_file" "infra_machineset_template" {
  count    = length(var.aws_worker_availability_zones)
  template = <<EOF
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${var.cluster_name}-${var.infra_random_id}
  name: ${var.cluster_name}-${var.infra_random_id}-infra-${var.aws_worker_availability_zones[count.index]}
  namespace: openshift-machine-api
spec:
  replicas: ${var.aws_infra_count_per_availability_zone}
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${var.cluster_name}-${var.infra_random_id}
      machine.openshift.io/cluster-api-machineset: ${var.cluster_name}-${var.infra_random_id}-infra-${var.aws_worker_availability_zones[count.index]}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${var.cluster_name}-${var.infra_random_id}
        machine.openshift.io/cluster-api-machine-role: infra
        machine.openshift.io/cluster-api-machine-type: infra
        machine.openshift.io/cluster-api-machineset: ${var.cluster_name}-${var.infra_random_id}-infra-${var.aws_worker_availability_zones[count.index]}
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/infra: ""
          node-role.kubernetes.io: infra
      providerSpec:
        value:
          ami:
            id: ${var.ami}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              # encrypted/kmsKey not needed - AMI is already encrypted with the CMK
              iops: ${var.aws_infra_root_volume_iops}
              volumeSize: ${var.aws_infra_root_volume_size}
              volumeType: ${var.aws_infra_root_volume_type}
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${var.cluster_name}-${var.infra_random_id}-worker-profile
          instanceType: ${var.aws_infra_instance_type}
          kind: AWSMachineProviderConfig
          metadataServiceOptions:
            authentication: Required
          placement:
            availabilityZone: ${var.aws_worker_availability_zones[count.index]}
            region: ${var.region}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${var.cluster_name}-${var.infra_random_id}-node
          subnet:
            id: ${data.aws_subnet.subnets[var.aws_worker_availability_zones[count.index]].id}
          tags:%{ for key, value in var.tags }
            - name: "${key}"
              value: "${value}"%{ endfor }
            - name: "kubernetes.io/cluster/${var.cluster_name}-${var.infra_random_id}"
              value: "owned"
          userDataSecret:
            name: worker-user-data
      taints:
      - effect: NoSchedule
        key: node-role.kubernetes.io/infra
        value: reserved
      - effect: NoExecute
        key: node-role.kubernetes.io/infra
        value: reserved
EOF
}
