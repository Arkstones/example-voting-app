#!/usr/bin/env bash
# terraform/up.sh - create (or update) the EKS cluster and connect kubectl to it.
#
# Usage: ./terraform/up.sh                 2 nodes (Capstone 1)
#        NODE_COUNT=3 ./terraform/up.sh    3 nodes (Capstone 2, Robot Shop + monitoring)
# Takes about 15 minutes the first time. Costs about $6-7/day while the cluster
# exists, so run ./terraform/down.sh when you are done.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

NODE_COUNT="${NODE_COUNT:-2}"

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
echo "== terraform apply (node_count=$NODE_COUNT) =="
terraform apply -input=false -var="node_count=$NODE_COUNT"

echo
echo "== connecting kubectl =="
region=$(terraform output -raw region)
name=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region "$region" --name "$name"

# The EKS module only uses node_count when the node group is first created
# (it ignores later changes to the desired size, so autoscalers can change it).
# So for an existing cluster, scale the node group directly when needed.
nodegroup=$(aws eks list-nodegroups --region "$region" --cluster-name "$name" --query 'nodegroups[0]' --output text)
current=$(aws eks describe-nodegroup --region "$region" --cluster-name "$name" --nodegroup-name "$nodegroup" \
    --query 'nodegroup.scalingConfig.desiredSize' --output text)
if [[ "$current" != "$NODE_COUNT" ]]; then
    echo
    echo "== scaling node group $nodegroup from $current to $NODE_COUNT nodes =="
    aws eks update-nodegroup-config --region "$region" --cluster-name "$name" --nodegroup-name "$nodegroup" \
        --scaling-config "minSize=1,maxSize=4,desiredSize=$NODE_COUNT" >/dev/null
    aws eks wait nodegroup-active --region "$region" --cluster-name "$name" --nodegroup-name "$nodegroup"
    # give new nodes a moment to register before waiting on them
    sleep 30
fi

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
