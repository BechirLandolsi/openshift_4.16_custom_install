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

resource "null_resource" "openshift_ready" {
  depends_on = [null_resource.openshift_install]

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        KUBECONFIG=installer-files/auth/kubeconfig oc -n openshift-ingress get service router-default
    EOT
  }
}

# Get ingress load balancer info
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

### DNS ROUTE - PUBLIC HOSTED ZONE (for external access)
resource "aws_route53_record" "ingress_dns_route" {
  zone_id = var.hosted_zone
  name    = join(".", ["*.apps", var.cluster_name, var.domain])
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress.dns_name
    zone_id                = data.aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

### DNS ROUTE - PRIVATE HOSTED ZONE (for internal cluster DNS resolution)
# The OpenShift installer creates a private hosted zone for internal DNS
# We MUST add the *.apps record there so pods can resolve oauth, console, etc.
data "aws_route53_zone" "private" {
  name         = "${var.cluster_name}.${var.domain}."
  private_zone = true

  depends_on = [null_resource.openshift_install]
}

resource "aws_route53_record" "ingress_dns_route_private" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = join(".", ["*.apps", var.cluster_name, var.domain])
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_lb.ingress.dns_name]
}

# Wait for DNS to propagate before checking cluster health
resource "null_resource" "wait_for_dns" {
  depends_on = [
    aws_route53_record.ingress_dns_route,
    aws_route53_record.ingress_dns_route_private
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<EOT
        echo "Waiting for DNS propagation (60 seconds)..."
        sleep 60
        echo "DNS records created. Verifying cluster operators..."
    EOT
  }
}

# Final check - cluster is fully operational
resource "null_resource" "openshift_installed" {
  depends_on = [null_resource.wait_for_dns]

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

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        echo "Checking cluster operators..."
        KUBECONFIG=installer-files/auth/kubeconfig oc get co
    EOT
  }

  # Wait for authentication operator to be available (with retries)
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        echo "Waiting for authentication operator..."
        for i in {1..30}; do
            if KUBECONFIG=installer-files/auth/kubeconfig oc get co authentication -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q "True"; then
                echo "✓ Authentication operator is available"
                exit 0
            fi
            echo "  Attempt $i/30: Authentication not ready yet, waiting 30s..."
            sleep 30
        done
        echo "⚠ Authentication operator not available after 15 minutes"
        KUBECONFIG=installer-files/auth/kubeconfig oc get co authentication
        exit 1
    EOT
  }
}
