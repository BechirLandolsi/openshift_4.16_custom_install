########################################################
##############   ROLE OCP CONTROL PLAN   ###############
########################################################

resource "aws_iam_role" "ocpcontrolplane" {
  name                 = var.control_plane_role_name
  permissions_boundary = var.ccoe_boundary
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  tags = merge( 
    var.tags,
    {
      Name = var.control_plane_role_name
    },
  )
}

data "aws_iam_policy_document" "ocpcontrolplane-policy" {
  statement {
    effect    = "Allow"
    actions   = [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:Describe*",
      "ec2:DetachVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:RevokeSecurityGroupIngress",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ocpcontrolplane-policy" {
  name        = var.ocpcontrolplane_policy # "ocpcontrolplane-policy"
  description = "OCP Control Plane Policy"
  policy      = data.aws_iam_policy_document.ocpcontrolplane-policy.json
}

resource "aws_iam_role_policy_attachment" "tf_ocpcontrolplane_node_AmazonEC2ContainerRegistryReadOnly" {
  role        = aws_iam_role.ocpcontrolplane.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ocpcontrolplane-attach" {
  role       = aws_iam_role.ocpcontrolplane.name
  policy_arn = aws_iam_policy.ocpcontrolplane-policy.arn
}

# Instance profile for control plane (created for installer compatibility)
resource "aws_iam_instance_profile" "ocpcontrolplane" {
  name = "${var.cluster_name}-${var.infra_random_id}-master-profile"
  role = aws_iam_role.ocpcontrolplane.name
  
  tags = var.tags
}


########################################################
##############   ROLE OCP WORKER NODE   ################
########################################################

resource "aws_iam_role" "ocpworkernode" {
  name                 = var.aws_worker_iam_role
  permissions_boundary = var.ccoe_boundary
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  tags = merge( 
    var.tags,
    {
      Name = var.aws_worker_iam_role
    },
  )
}

data "aws_iam_policy_document" "ocpworkernode-policy" {
  statement {
    effect    = "Allow"
    actions   = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions"
    ]
    resources = ["*"]
  }
  
  statement {
    effect    = "Allow"
    actions   = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ocpworkernode-policy" {
  name        = var.ocpworkernode_policy #"ocpworkernode-policy"
  description = "OCP Worker Policy with KMS permissions"
  policy      = data.aws_iam_policy_document.ocpworkernode-policy.json
  
  # Force recreation when policy document changes
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "tf_ocpworkernode_node_AmazonEC2ContainerRegistryReadOnly" {
  role        = aws_iam_role.ocpworkernode.name
  policy_arn  = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ocpworkernode-attach" {
  role       = aws_iam_role.ocpworkernode.name
  policy_arn = aws_iam_policy.ocpworkernode-policy.arn
}

# Instance profile for worker nodes (created for installer compatibility)
resource "aws_iam_instance_profile" "ocpworkernode" {
  name = "${var.cluster_name}-${var.infra_random_id}-worker-profile"
  role = aws_iam_role.ocpworkernode.name
  
  tags = var.tags
}

data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    sid = "1"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.main.id}"]
    }
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.ocp.id}/*",
      "arn:aws:s3:::${aws_s3_bucket.ocp.id}"
    ]
  }
}

########################################################
##############   KMS KEY POLICY FOR EBS   ##############
########################################################

# This resource automatically updates the KMS key policy after IAM roles are created
# to grant OpenShift roles permission to use the KMS key for EBS encryption
# Uses null_resource with AWS CLI for compatibility with older AWS provider versions

locals {
  # Combine Terraform-managed roles with any additional roles (e.g., CSI driver)
  kms_role_arns = concat(
    [
      aws_iam_role.ocpcontrolplane.arn,
      aws_iam_role.ocpworkernode.arn
    ],
    var.kms_additional_role_arns
  )
  
  # Build the KMS policy JSON
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Id      = "openshift-ebs-encryption-policy"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow OpenShift roles to use the key"
        Effect = "Allow"
        Principal = {
          AWS = local.kms_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow OpenShift roles to manage grants"
        Effect = "Allow"
        Principal = {
          AWS = local.kms_role_arns
        }
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })
}

resource "null_resource" "kms_key_policy" {
  # Trigger update when roles change
  triggers = {
    controlplane_role_arn = aws_iam_role.ocpcontrolplane.arn
    worker_role_arn       = aws_iam_role.ocpworkernode.arn
    additional_roles      = join(",", var.kms_additional_role_arns)
    kms_key_id            = data.aws_kms_alias.ec2_cmk_arn.target_key_id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      echo "Updating KMS key policy for OpenShift EBS encryption..."
      
      # Write policy to temp file
      cat > /tmp/kms-policy-$$.json << 'POLICY'
      ${local.kms_policy}
      POLICY
      
      # Apply the policy
      aws kms put-key-policy \
        --key-id ${data.aws_kms_alias.ec2_cmk_arn.target_key_id} \
        --policy-name default \
        --policy file:///tmp/kms-policy-$$.json \
        --region ${var.region}
      
      # Cleanup
      rm -f /tmp/kms-policy-$$.json
      
      echo "KMS key policy updated successfully."
    EOT
  }

  # Ensure roles are created before updating KMS policy
  depends_on = [
    aws_iam_role.ocpcontrolplane,
    aws_iam_role.ocpworkernode
  ]
}
