variable "region" {
  description = "AWS region for the cluster"
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "Uga-vote-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the control plane and nodes"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for the worker nodes (c7i-flex.large = 2 vCPU, 4 GiB, allowed on the AWS free plan)"
  type        = string
  default     = "c7i-flex.large"
}

variable "node_count" {
  description = "How many worker nodes to run (2 for Capstone 1, 3 for Capstone 2)"
  type        = number
  default     = 2
}

variable "app_namespace" {
  description = "Kubernetes namespace the voting app is deployed into"
  type        = string
  default     = "uga-vote"
}
