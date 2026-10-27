#!/usr/bin/env bash
# terraform/down.sh - delete the EKS cluster and everything Terraform created.
#
# Usage: ./terraform/down.sh
#
# Some AWS resources are created by Kubernetes, not by Terraform:
#   - a Service of type LoadBalancer creates an AWS load balancer
#   - a PersistentVolumeClaim creates an EBS disk
# Terraform does not know about these, so they would be left behind (and keep
# costing money). This script deletes them from Kubernetes first, which makes
# AWS remove them, and only then runs terraform destroy.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -f terraform.tfstate ]] || ! terraform state list >/dev/null 2>&1; then
    echo "No Terraform state here, nothing to destroy."
    exit 0
fi

region=$(terraform output -raw region 2>/dev/null || echo "")
name=$(terraform output -raw cluster_name 2>/dev/null || echo "")

if [[ -n "$name" ]] && aws eks describe-cluster --region "$region" --name "$name" >/dev/null 2>&1; then
    aws eks update-kubeconfig --region "$region" --name "$name" >/dev/null

    echo "== removing Kubernetes-created AWS resources =="
    # load balancers: delete every Service of type LoadBalancer
    kubectl get svc --all-namespaces \
        -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' |
    while read -r ns svc; do
        [[ -n "$ns" ]] || continue
        echo "deleting LoadBalancer service $ns/$svc"
        kubectl delete svc -n "$ns" "$svc" --wait=true
    done

    # EBS disks: deleting the claims makes the CSI driver delete the volumes
    echo "deleting PersistentVolumeClaims"
    kubectl delete pvc --all --all-namespaces --wait=true || true

    # give AWS a moment to finish removing the load balancers and disks
    sleep 30
fi

echo
echo "== terraform destroy =="
terraform destroy -input=false

echo
echo "Cluster destroyed. Check the EC2 > Load Balancers and EC2 > Volumes pages"
echo "in the AWS console if you want to be sure nothing is left."
