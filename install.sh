#!/bin/bash

### VARIABLES ###
CLUSTER_NAME=clearavenue-cluster
REGION=us-east-2

start=$(date +%s.%N)

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
  echo " "
}

function usage {
  echo "Usage: $(basename $0) [ -destroy ]"
  exit
}

if [[ $# -gt 1 ]]; then
  usage
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "-destroy" ]]; then
    usage
  else
    echo_header "Destroying infrastructure"
    chmod u+x destroy.sh
    ./destroy.sh
    exit
  fi
fi

echo_header "OneClick Setup: ($(date))"

# install tools
echo_header "Install tools"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create cluster
echo_header "Create cluster"
eksctl create cluster -f cluster/cluster.yaml

sleep 30

# Update kubectl
echo_header "Update kubectl"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Install cert manager
echo_header "Install cert manager"
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.10.1 \
  --set installCRDs=true \
  --set serviceAccount.create=false \
  --set serviceAccount.name=sa-cert-manager \
  --set securityContext.fsGroup=1001 \
  --set securityContext.runAsUser=1001

# Install istio
istioctl install -y --set profile=demo

# Install external-dns
echo_header "Install external-dns"
kubectl apply -f cluster/external-dns-deployment.yaml

# Create cluster issuer and cert
echo_header "Install cluster issuer and cert"
kubectl apply -f cluster/certificate/cluster-issuer.yaml
kubectl apply -f cluster/certificate/cluster-cert.yaml

# Install Istio Gateway
echo_header "Install Istio Gateway"
kubectl apply -f istio/istio-gateway.yaml

# Install ArgoCD
kubectl apply -f argocd/argocd-namespace.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.4.7/manifests/install.yaml
