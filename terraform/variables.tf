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
  description = "EC2 instance type for the worker nodes (t3.medium = 2 vCPU, 4 GiB)"
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  description = "How many worker nodes to run (2 for Capstone 1, 3 for Capstone 2)"
  type        = number
  default     = 2
}
