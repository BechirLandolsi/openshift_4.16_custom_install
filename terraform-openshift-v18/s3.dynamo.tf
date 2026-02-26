resource "aws_kms_key" "s3_terraform_state" {
  description             = "KMS key for Terraform state S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "s3_terraform_state" {
  name          = "alias/s3-terraform-state-${var.cluster_name}"
  target_key_id = aws_kms_key.s3_terraform_state.id
}

resource "aws_s3_bucket" "s3-terraform-state-storage" {
  bucket = "${lower(var.cluster_name)}-${lower(var.infra_random_id)}-terraform-remote-state-storage-s3"

  force_destroy = true

  tags = var.tags
}

# Versioning configuration (separate resource as of AWS provider 4.x)
resource "aws_s3_bucket_versioning" "s3-terraform-state-storage" {
  bucket = aws_s3_bucket.s3-terraform-state-storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption configuration (separate resource as of AWS provider 4.x)
resource "aws_s3_bucket_server_side_encryption_configuration" "s3-terraform-state-storage" {
  bucket = aws_s3_bucket.s3-terraform-state-storage.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_terraform_state.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_dynamodb_table" "terraform-locks" {
  name         = "${var.cluster_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.s3-terraform-state-storage.bucket
  policy =<<EOF
{
  "Version": "2012-10-17",
  "Id": "RequireEncryption",
   "Statement": [
    {
      "Sid": "RequireEncryptedTransport",
      "Effect": "Deny",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.s3-terraform-state-storage.bucket}/*"],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      },
      "Principal": "*"
    }
  ]
}
EOF
}
