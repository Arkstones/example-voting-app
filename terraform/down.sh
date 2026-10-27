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
    # Deleting an app namespace deletes everything in it: the pods, the
    # LoadBalancer services (so AWS removes the load balancers) and the disk
    # claims (so the EBS CSI driver deletes the volumes). Deleting a claim on
    # its own would hang while a pod still uses it, so namespaces are simpler.
    # System namespaces (default, kube-*) are left alone.
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        case "$ns" in
            default|kube-system|kube-public|kube-node-lease) continue ;;
        esac
        echo "deleting namespace $ns"
        kubectl delete namespace "$ns" --wait=true --timeout=10m
    done

    # anything left in the default namespace
    kubectl delete svc --field-selector spec.type=LoadBalancer -n default --wait=true || true
    kubectl delete pvc --all -n default --wait=true --timeout=5m || true

    # give AWS a moment to finish removing the load balancers and disks
    sleep 30
fi

echo
echo "== terraform destroy =="
terraform destroy -input=false

echo
echo "Cluster destroyed. Check the EC2 > Load Balancers and EC2 > Volumes pages"
echo "in the AWS console if you want to be sure nothing is left."
echo "(The github-deployer IAM user in terraform/ci-user is kept on purpose: it is"
echo " free, and keeping it means the GitHub secret keeps working.)"
