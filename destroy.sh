#!/bin/bash

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
  echo " "
}

echo_header "Remove virtual services and DNS entries"
kubectl delete virtualservice --all --all-namespaces
sleep 15

echo_header "Remove external_dns"
kubectl delete -f cluster/external-dns-deployment.yaml

echo_header "Remove istio"
istioctl uninstall -y --purge

echo_header "Destroy cluster"
eksctl delete cluster -f cluster/cluster.yaml

echo_header "Clean up jenkins temp files"
rm jenkins/jenkins-cli.jar
