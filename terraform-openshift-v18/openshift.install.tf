resource "null_resource" "openshift_install" {
  depends_on = [local_file.cluster_ingress, aws_s3_object.keys, null_resource.save_manifests]

  triggers = {
    hosted_zone  = var.hosted_zone
    cluster_name = var.cluster_name
    domain       = var.domain
    bucket       = join("-", [lower(var.cluster_name), lower(var.infra_random_id), "terraform-remote-state-storage-s3"])
    tfvars_file  = var.tfvars_file
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = "nohup sh create-cluster.sh 2>&1 | tee output/openshift-install.log &"
  }

  provisioner "local-exec" {
    when = destroy
    interpreter = ["bash","-c"]
    command     = <<EOT
        sh clean-cluster.sh ${self.triggers.hosted_zone} ${self.triggers.cluster_name} ${self.triggers.domain} ${self.triggers.bucket} ${self.triggers.tfvars_file}
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

# NOTE: DNS records are created by create-private-dns.sh during install
# This is necessary because authentication operator needs DNS BEFORE install completes
# The script creates *.apps record in the private zone for internal resolution

# Wait for DNS to be created by the background script
resource "null_resource" "wait_for_dns" {
  depends_on = [null_resource.openshift_ready]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<EOT
        echo "Waiting for DNS record creation (by background script)..."
        for i in {1..30}; do
            if grep -q "Successfully created" output/private-dns.log 2>/dev/null; then
                echo "✓ DNS record created by background script"
                break
            fi
            if grep -q "Record already exists" output/private-dns.log 2>/dev/null; then
                echo "✓ DNS record already exists"
                break
            fi
            echo "  Waiting for DNS... (attempt $i/30)"
            sleep 10
        done
        echo "DNS setup complete."
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
