# Terraform: EKS cluster `Uga-vote-cluster`

Creates the Kubernetes cluster the voting app runs on.

| What | Value |
|---|---|
| Cloud / region | AWS `eu-north-1` (Stockholm) |
| Network | The account's **default VPC** and its default subnets (no new VPC, no NAT gateway) |
| Cluster | EKS, Kubernetes 1.36, public API endpoint |
| Nodes | 1 managed node group, 2 × `t3.medium` (Amazon Linux 2023) |
| Add-ons | vpc-cni, kube-proxy, coredns, eks-pod-identity-agent, aws-ebs-csi-driver |
| Module | [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) v21 |

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform and AWS provider versions |
| `variables.tf` | Region, cluster name, Kubernetes version, node size and count |
| `main.tf` | Default VPC lookup, the EKS module, IAM role for the EBS disk driver |
| `outputs.tf` | Cluster name, endpoint, and the `kubectl` connect command |
| `up.sh` | `terraform init` + `apply`, then connects `kubectl` and waits for nodes |
| `down.sh` | Removes Kubernetes-made load balancers and disks, then `terraform destroy` |

## Usage

Needs the AWS CLI logged in (`aws sts get-caller-identity`), Terraform and kubectl.

```bash
./terraform/up.sh      # create the cluster, about 15 minutes
kubectl get nodes      # 2 nodes, Ready
./terraform/down.sh    # delete everything, about 10 minutes
```

Change a setting without editing files, for example 3 nodes for Capstone 2:

```bash
cd terraform && terraform apply -var="node_count=3"
```

## Design choices

- **Default VPC.** The brief asks for it, and its subnets are public, so the nodes reach the internet without a NAT gateway (which would cost about $32/month on its own).
- **Public API endpoint.** I need to reach the cluster from my laptop and from GitHub Actions. Access still needs valid AWS credentials and an EKS access entry.
- **Cluster creator is admin.** `enable_cluster_creator_admin_permissions` gives the IAM user that ran Terraform (`robert-devops`) admin rights in Kubernetes. Without it, `kubectl` returns "Unauthorized".
- **EBS disk driver with Pod Identity.** Only the driver's own service account gets permission to create disks, not every pod on the node.
- **`vpc-cni` before nodes.** Nodes can't become Ready until pod networking exists, so `before_compute = true` installs it first.
- **Local state.** `terraform.tfstate` stays on my machine and is ignored by Git, because it can contain sensitive values. Remote state in S3 is an optional stretch goal.

## Cost

About **$5/day** while the cluster exists ($0.10/hour for the EKS control plane, plus two `t3.medium` nodes). It's close to $0 after `down.sh`. A zero-spend budget alert in AWS Budgets emails me if anything is left running.

## Destroy and recreate

The brief requires showing the environment rebuilds from code:

```bash
./terraform/down.sh
./terraform/up.sh
kubectl get nodes
```
