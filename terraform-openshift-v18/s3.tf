resource "aws_s3_bucket" "ocp" {
  bucket        = var.s3_bucket_name_oidc
  force_destroy = true
  tags = merge( 
    var.tags,
    {
      Name = var.s3_bucket_name_oidc
    },
    {
      "openshift.io/cloud-credential-operator/${var.cluster_name}" = "owned"
    }
  )
}

resource "aws_s3_bucket_ownership_controls" "ocp" {
  bucket = aws_s3_bucket.ocp.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
} 

resource "aws_s3_bucket_acl" "ocp" {
  depends_on = [aws_s3_bucket_ownership_controls.ocp]
  bucket     = aws_s3_bucket.ocp.id
  acl        = "private"
}

resource "aws_s3_bucket_policy" "oidc_bucket_policy" {
  bucket = aws_s3_bucket.ocp.id
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json
}

resource "aws_s3_bucket_public_access_block" "ocp" {
  bucket                  = aws_s3_bucket.ocp.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
