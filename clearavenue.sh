#!/bin/bash
set -e

START="$(date +%s)"

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

echo_header "Terraform init/apply"
terraform init
terraform apply --auto-approve

##### Environments #####
for NAMESPACE in prod stage dev
do
  echo_header "Creating $NAMESPACE environment"
  kubectl create namespace $NAMESPACE

  kubectl -n ${NAMESPACE} create secret generic aws-keys \
    --from-literal=aws_access=$AWS_ACCESS_KEY \
    --from-literal=aws_secret=$AWS_SECRET_KEY

  kubectl -n ${NAMESPACE} create rolebinding ${NAMESPACE}-role \
    --clusterrole=cluster-admin \
    --serviceaccount=default:default

done

# ArgoCD
echo_header "Install ArgoCD"
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl -n argocd get service argocd-server -o jsonpath='{.status.loadBalancer.ingress}' | jq -r '.[].hostname' > argocd-info.txt
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d >> argocd-info.txt

export GITHUB_TOKEN=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
envsubst < argocd-repositories.yaml | kubectl apply -n argocd -f -

# kubernetes dashboard
#echo_header "Install Kubernetes Dashboard"
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml
#kubectl proxy &

kubectl cluster-info
DURATION=$[ $(date +%s) - ${START} ]
echo "Finished in " ${DURATION}
