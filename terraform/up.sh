#!/usr/bin/env bash
# terraform/up.sh - create (or update) the EKS cluster and connect kubectl to it.
#
# Usage: ./terraform/up.sh
# Takes about 15 minutes the first time. Costs about $6-7/day while the cluster
# exists, so run ./terraform/down.sh when you are done.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for tool in aws terraform kubectl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed"; exit 1; }
done

echo "== AWS identity =="
aws sts get-caller-identity --query Arn --output text

echo
echo "== deploy user for GitHub Actions (terraform/ci-user) =="
# long-lived and free, never destroyed by down.sh; usually "No changes"
terraform -chdir=ci-user init -input=false >/dev/null
terraform -chdir=ci-user apply -input=false -auto-approve

echo
echo "== terraform init =="
terraform init -input=false

echo
echo "== terraform apply =="
terraform apply -input=false

echo
echo "== connecting kubectl =="
region=$(terraform output -raw region)
name=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region "$region" --name "$name"

echo
echo "== nodes =="
# nodes can take a minute to report Ready after the node group is created
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o wide

echo
echo "== namespace and storage class =="
kubectl apply -f ../k8s/cluster-setup.yaml

echo
echo "Cluster $name is up in $region."
echo "Remember: ./terraform/down.sh when you are finished, to stop the charges."
