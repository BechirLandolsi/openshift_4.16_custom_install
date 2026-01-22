resource "null_resource" "configuration_OIDC" {
  depends_on = [null_resource.aws_key_pair]

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		mkdir -p output
    EOT
  }

  provisioner "local-exec" {
    command     = "ccoctl aws create-identity-provider --name=${var.cluster_name} --region=${var.region} --public-key-file=output/serviceaccount-signer.public --output-dir=output/ --dry-run"
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sed -i "s/<enter_tls_fingerprint_for_issuer_url_here>/${aws_iam_openid_connect_provider.default.thumbprint_list[0]}/" output/04-iam-identity-provider.json
	EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
        sed -i "s/https:\/\/${var.cluster_name}[a-z.-].*/https:\/\/${aws_cloudfront_distribution.s3_distribution.domain_name}\",/" output/04-iam-identity-provider.json
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sed -i "s/https:\/\/${var.cluster_name}[a-z.-].*\//https:\/\/${aws_cloudfront_distribution.s3_distribution.domain_name}\//" output/02-openid-configuration
	EOT
  }
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sed -i "s/https:\/\/${var.cluster_name}[a-z.-].*/https:\/\/${aws_cloudfront_distribution.s3_distribution.domain_name}\",/" output/02-openid-configuration
	EOT
  }
  provisioner "local-exec" {
    interpreter = ["bash","-c"]
    command     = <<EOT
		sed -i "s/https:\/\/[a-z.-].*/https:\/\/${aws_cloudfront_distribution.s3_distribution.domain_name}/" output/manifests/cluster-authentication-02-config.yaml
	EOT
  }
}

resource "null_resource" "extract_cred_request" { 
  depends_on = [null_resource.configuration_OIDC]

  provisioner "local-exec" {
    command     = "oc adm release extract --credentials-requests --cloud=aws --to=output/credrequests ${var.release_image}"
    #command = "echo en attente d ouverture de flux"
  }
}

resource "null_resource" "create_roles" {
  depends_on = [null_resource.extract_cred_request]

  provisioner "local-exec" {
    command     = <<EOT
		ccoctl aws create-iam-roles --name=${var.cluster_name} --region=${var.region} --credentials-requests-dir=output/credrequests --identity-provider-arn=${aws_iam_openid_connect_provider.default.arn}  --output-dir output --permissions-boundary-arn ${var.ccoe_boundary}
	EOT
  }   

}

resource "aws_s3_object" "keys" {
  depends_on = [null_resource.create_roles]

  bucket = aws_s3_bucket.ocp.id
  key    = "keys.json"
  source = "output/03-keys.json"
}

resource "aws_s3_object" "openid" {
  depends_on = [null_resource.create_roles]

  bucket = aws_s3_bucket.ocp.id
  key    = ".well-known/openid-configuration"
  source = "output/02-openid-configuration"
}
