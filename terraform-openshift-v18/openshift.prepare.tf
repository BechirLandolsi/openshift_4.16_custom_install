resource "null_resource" "openshift_prepare" {
  depends_on = [local_file.install_config,null_resource.create_roles]
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
	command     = "ForceOpenshiftInfraIDRandomPart=${var.infra_random_id} openshift-install create manifests --dir=installer-files"
  }
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = "cp output/manifests/* installer-files/manifests/"
  }
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = "cp -a output/tls installer-files"
  }
}

resource "local_file" "cluster_ingress" {
  depends_on = [null_resource.openshift_prepare]

  content  =  data.template_file.cluster_ingress.rendered
  filename =  "installer-files/manifests/cluster-ingress-default-ingresscontroller.yaml"
}


resource "local_file" "infra_machinesets" {
  depends_on = [null_resource.openshift_prepare]

  count    = length(var.aws_worker_availability_zones)
  filename = "installer-files/openshift/99_openshift-cluster-api_infra-machineset-${count.index}.yaml"
  content  = template_file.infra_machineset_template[count.index].rendered
}


resource "null_resource" "save_manifests" {
  depends_on = [local_file.infra_machinesets]
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = "mkdir -p init_setup"
  }
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = "cp -a installer-files init_setup"
  }
}

