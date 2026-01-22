resource "null_resource" "openshift_install" {
  depends_on = [local_file.cluster_ingress, aws_s3_object.keys, null_resource.save_manifests]

  triggers = {
    hosted_zone = var.hosted_zone
    cluster_name = var.cluster_name
    domain = var.domain
    bucket = join("-", [lower(var.cluster_name), lower(var.infra_random_id), "terraform-remote-state-storage-s3"])
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    #command     = "nohup sh create-cluster.sh >output/openshift-install.log 2>&1 &"
    command     = "nohup sh create-cluster.sh 2>&1 | tee output/openshift-install.log &"
  }

  provisioner "local-exec" {
    when = destroy
    interpreter = ["bash","-c"]
    command     = <<EOT
        sh clean-cluster.sh ${self.triggers.hosted_zone} ${self.triggers.cluster_name} ${self.triggers.domain} ${self.triggers.bucket}
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sh wait.sh 1 30 output/openshift-install.log "KUBECONFIG=installer-files/auth/kubeconfig oc -n openshift-ingress get service router-default" 
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        sh save-cluster-states.sh ${self.triggers.bucket}                        
    EOT
  }

}

resource "null_resource" "openshift_installed" {
  depends_on = [null_resource.openshift_install]

  triggers = {
    bucket = join("-", [lower(var.cluster_name), lower(var.infra_random_id), "terraform-remote-state-storage-s3"])
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sh wait.sh 1 15 output/openshift-install.log "grep \"Install complete!\" output/openshift-install.log"
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        sh save-cluster-states.sh ${self.triggers.bucket}
    EOT
  }

  // DEBUG JENKINS CONTEXT
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        KUBECONFIG=installer-files/auth/kubeconfig oc get co
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        KUBECONFIG=installer-files/auth/kubeconfig oc get co | grep authentication | awk '{if ($3=="True") exit 0; else exit 1;;}'
    EOT
  }

}

resource "null_resource" "openshift_ready" {
  depends_on = [null_resource.openshift_install]

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        KUBECONFIG=installer-files/auth/kubeconfig oc -n openshift-ingress get service router-default
    EOT
  }
}

data "external" "get_ingress_lb" {
  depends_on = [null_resource.openshift_ready]

  query = {
    bucket = join("-", [lower(var.cluster_name), lower(var.infra_random_id), "terraform-remote-state-storage-s3"])
  }

  program = ["bash", "get-ingress-lb.sh"]
}

data "aws_lb" "ingress" {
  arn = data.external.get_ingress_lb.result.LoadBalancerArn 
}

### DNS ROUTE ELB TO ADD TO HOSTED ZONE
resource "aws_route53_record" "ingress_dns_route" {
  zone_id = var.hosted_zone
  name    = join(".", ["*.apps", var.cluster_name, var.domain])
  type    = "A"

  alias {
    name = "${data.aws_lb.ingress.dns_name}"
    zone_id = "${data.aws_lb.ingress.zone_id}"
    evaluate_target_health = true
  }
}

