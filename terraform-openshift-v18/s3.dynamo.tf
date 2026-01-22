resource "aws_kms_key" "s3_skw_ocp_plaasma" {
  description             = "SKW OCP S3 PLaaSMA Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "s3_skw_ocp_plaasma" {
  name          = "alias/s3-ocp-plaasma-key-${var.cluster_name}"
  target_key_id = aws_kms_key.s3_skw_ocp_plaasma.id
}

resource "aws_s3_bucket" "s3-plaasma-terraform-state-storage" {
  bucket = "${lower(var.cluster_name)}-${lower(var.infra_random_id)}-terraform-remote-state-storage-s3"

  force_destroy = true

  versioning {
    enabled = true
  }

  # Enable server-side encryption by default
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_skw_ocp_plaasma.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

 tags = var.tags
}

resource "aws_dynamodb_table" "dt-plaasma-terraform-locks" {
  name         = "${var.cluster_name}-terraform-up-and-running-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags

}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.s3-plaasma-terraform-state-storage.bucket
  policy =<<EOF
{
  "Version": "2012-10-17",
  "Id": "RequireEncryption",
   "Statement": [
    {
      "Sid": "RequireEncryptedTransport",
      "Effect": "Deny",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.s3-plaasma-terraform-state-storage.bucket}/*"],
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
