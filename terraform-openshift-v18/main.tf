resource "aws_cloudfront_origin_access_identity" "main" {
  comment = var.s3_bucket_name_oidc
}

locals {
  s3_origin_id = aws_s3_bucket.ocp.bucket_regional_domain_name
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.ocp.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    viewer_protocol_policy = "https-only"
  }
  
  comment             = "${var.cluster_name}"
  enabled             = true
  price_class         = "PriceClass_All"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.cluster_name}"
    "webacl:auto" = "default",
    "security:webacl:auto" = "no"
  }
}

data "tls_certificate" "thumbprint" {
  url = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
}


#output "thumbprint_tls" {
#  description = "The thumprint of the certificate CN=*.cloudfront.net"
  ####### The first certificate is for CN=Starfield Services Root Certificate Authority - G2
  ####### The second certificate is for CN=Amazon Root CA 1,O=Amazon,C=US
  ####### The third certificate is for CN=Amazon RSA 2048 M01,O=Amazon,C=US
  ####### To see the chain switch the value line
  # value       = data.tls_certificate.thumbprint.certificates
#  value       = data.tls_certificate.thumbprint.certificates[3].sha1_fingerprint
#}

resource "aws_iam_openid_connect_provider" "default" {
  url = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
  client_id_list  = ["openshift","sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.thumbprint.certificates[3].sha1_fingerprint]
}

resource "null_resource" "aws_key_pair" {
  depends_on = [aws_iam_openid_connect_provider.default]

  provisioner "local-exec" {
   interpreter = ["bash","-c"]
    command     = "ccoctl aws create-key-pair --output-dir output"
  }
}

