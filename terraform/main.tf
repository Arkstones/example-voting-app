provider "aws" {
  region = var.region

  # every resource Terraform creates gets these tags, so it is easy to
  # find them (and their cost) in the AWS console
  default_tags {
    tags = {
      Project   = "uga-vote"
      ManagedBy = "terraform"
      Owner     = "robert-olwoch"
    }
  }
}

# ---------------------------------------------------------------------------
# Network: use the default VPC that every AWS account already has.
# Its subnets are public, so the nodes get public IPs and can pull images
# without a NAT gateway (a NAT gateway would cost about $1 a day extra).
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# one default subnet per availability zone (eu-north-1a, 1b, 1c)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# ---------------------------------------------------------------------------
# EKS cluster, built with the community module
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # AWS defaults to EXTENDED support, which costs $0.60/hour instead of $0.10
  # once a Kubernetes version gets old. STANDARD keeps the cheap price
  # (AWS upgrades the cluster when standard support ends).
  upgrade_policy = {
    support_type = "STANDARD"
  }

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  # reach the Kubernetes API from my laptop and from GitHub Actions
  # (the module default is private only)
  endpoint_public_access = true

  # make the IAM user that runs Terraform (robert-devops) a cluster admin,
  # otherwise kubectl gets "Unauthorized" right after the cluster is created
  enable_cluster_creator_admin_permissions = true

  # No IAM OIDC provider (IRSA): the AWS free plan blocks
  # iam:CreateOpenIDConnectProvider, and Pod Identity (used below for the
  # EBS CSI driver) is the newer way to give pods AWS permissions anyway.
  enable_irsa = false

  # EKS add-ons, installed and kept up to date by AWS
  addons = {
    # networking: must exist before nodes join, or they never become Ready
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    # lets pods get EBS disks (PersistentVolumes), needed for Robot Shop in Capstone 2.
    # Its controller gets AWS permissions through Pod Identity (role below).
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 4
      desired_size = var.node_count

      labels = {
        project = "uga-vote"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# IAM role for the EBS CSI driver.
# Pod Identity lets only the driver's service account use this role, instead
# of giving disk permissions to every pod on the node.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
