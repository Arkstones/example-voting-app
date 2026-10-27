# ---------------------------------------------------------------------------
# terraform/ci-user: a separate, limited login for the GitHub Actions deploy job.
#
# This lives in its own folder (its own state) on purpose: the cluster is
# destroyed and recreated often, but this user and its access key should
# survive that, so the GitHub secret keeps working. It costs nothing.
#
# The usual way (GitHub OIDC -> IAM role, no stored keys) needs an IAM OIDC
# provider, which the AWS free plan blocks. So the pipeline uses an IAM user
# whose access key is stored as a GitHub secret. To keep the damage small if
# that key ever leaked, this user can only:
#   - in AWS: look up the one cluster (eks:DescribeCluster)
#   - in Kubernetes: edit things in the app's namespace (access entry, created
#     with the cluster in ../main.tf)
#
# The access key is NOT created here, because Terraform would then keep the
# secret in its state file. It is created once in the AWS console and pasted
# straight into GitHub secrets.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }
}

variable "region" {
  description = "AWS region of the cluster"
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster the deploy user may describe"
  type        = string
  default     = "Uga-vote-cluster"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "uga-vote"
      ManagedBy = "terraform"
      Owner     = "robert-olwoch"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_user" "github_deployer" {
  name = "github-deployer"
}

resource "aws_iam_user_policy" "github_deployer" {
  name = "describe-${var.cluster_name}"
  user = aws_iam_user.github_deployer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
    }]
  })
}

output "user_name" {
  description = "Create an access key for this user in the AWS console"
  value       = aws_iam_user.github_deployer.name
}

output "user_arn" {
  value = aws_iam_user.github_deployer.arn
}
