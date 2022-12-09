#!/bin/bash

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
  echo " "
}

echo_header "Remove external_dns"
kubectl delete -f cluster/external-dns-deployment.yaml

echo_header "Remove istio"
istioctl uninstall -y --purge

echo_header "Destroy cluster"
eksctl delete cluster -f cluster/cluster.yaml
