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
