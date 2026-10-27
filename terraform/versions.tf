terraform {
  # the EKS module v21 needs Terraform 1.5.7 or newer
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }

  # State is kept locally in terraform.tfstate (ignored by Git).
  # Moving it to S3 is one of the optional stretch goals.
}
