#!/bin/bash

### VARIABLES ###
CLUSTER_NAME=clearavenue-cluster
REGION=us-east-2
CERTS=/tmp/devsecops-cluster/letsencrypt

start=$(date +%s.%N)

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
  echo " "
}

function wait_website_ready() {
   check_web=$(curl -j -s --head --request GET $1 --cacert $CERTS/StagingArtificialApricotR3.crt | grep "200\|403" > /dev/null && echo "READY" || echo "NOT_READY")
   #check_web=$(curl -j -s --head --request GET $1 | grep "200\|403" > /dev/null && echo "READY" || echo "NOT_READY")
   while [ $check_web != "READY" ]; do
      echo "$1 not ready"
      sleep 30
      check_web=$(curl -j -s --head --request GET $1 --cacert $CERTS/StagingArtificialApricotR3.crt | grep "200\|403" > /dev/null && echo "READY" || echo "NOT_READY")
      #check_web=$(curl -j -s --head --request GET $1 | grep "200\|403" > /dev/null && echo "READY" || echo "NOT_READY")
   done
   echo "$1 ready"
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
echo_header "Install ArgoCD"
cd argocd
kubectl apply -f argocd-namespace.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl get -n argocd configmap argocd-cmd-params-cm -o yaml > argocd-cmd-params-cm.yaml
echo "data:" >> argocd-cmd-params-cm.yaml
echo "  server.insecure: \"true\"" >> argocd-cmd-params-cm.yaml
kubectl apply -f argocd-cmd-params-cm.yaml
kubectl rollout restart deploy -n argocd argocd-server
kubectl apply -f argocd-virtualservice.yaml
ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d )
echo $ARGOCD_PWD

sleep 30

while [[ $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for argocd pod" && sleep 1; done
wait_website_ready "https://argocd.cluster.clearavenue.com"

# Setup ArgoCD apps
echo_header "Deploy ArgoCD applications"
envsubst < argocd-repositories.yaml | kubectl apply -n argocd -f -
kubectl apply -n argocd -f apps-application.yaml
cd ..

# Configure Jenkins
echo_header "Configure Jenkins after 1 minute..."
cd jenkins

sleep 60

while [[ $(kubectl get pods -n jenkins -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for jenkins pod" && sleep 1; done
wait_website_ready "https://jenkins.cluster.clearavenue.com"

initialAdminPassword=$(kubectl exec -n jenkins $(kubectl get pods -n jenkins -o jsonpath="{.items[0].metadata.name}") -- cat /var/jenkins_home/secrets/initialAdminPassword)
wget https://jenkins.cluster.clearavenue.com/jnlpJars/jenkins-cli.jar --no-hsts --no-check-certificate
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth admin:$initialAdminPassword groovy = < generate-user-and-token.groovy

java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin trilead-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin cloudbees-folder
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin antisamy-markup-formatter
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jdk-tool
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin structs
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-step-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin token-macro
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin build-timeout
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin credentials
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin plain-credentials
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ssh-credentials
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin credentials-binding
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin scm-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin timestamper
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin script-security
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-support
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin durable-task
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-durable-task-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin plugin-util-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin font-awesome-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin popper-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jquery3-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin bootstrap4-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin snakeyaml-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jackson2-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin echarts-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin junit
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin matrix-project
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin command-launcher
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin resource-disposer
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ws-cleanup
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ant
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin bouncycastle-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ace-editor
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jquery-detached
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-scm-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-cps
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-job
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin apache-httpcomponents-client-4-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin display-url-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin mailer
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-basic-steps
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gradle
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-milestone-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-input-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-stage-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-graph-analysis
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-rest-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin handlebars
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin momentjs
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-stage-view
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-build-step
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-model-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-model-extensions
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jsch
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin git-client
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin git-server
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-cps-global-lib
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin branch-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-multibranch
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-stage-tags-metadata
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-model-definition
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin lockable-resources
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin workflow-aggregator
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin okhttp-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin github-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin git
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin github
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin github-branch-source
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-github-lib
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ssh-slaves
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pam-auth
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ldap
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin email-ext
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin checks-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jjwt-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin matrix-auth
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin ssh
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin role-strategy
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin javadoc
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin job-dsl
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin maven-plugin
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin strict-crumb-issuer
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gitlab-plugin
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gitlab-oauth
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gitlab-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gitlab-logo
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin gitlab-branch-source
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin dependency-check-jenkins-plugin
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin warnings-ng
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-utility-steps
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin jacoco
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin configuration-as-code
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin configuration-as-code-groovy
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin configuration-as-code-secret-ssm
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin pipeline-maven
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin greenballs
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin blueocean
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin kubernetes
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin kubernetes-cli
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin docker-plugin
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin docker-workflow
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin docker-commons
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin docker-java-api
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 install-plugin docker-build-step

java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 restart
sleep 30

# delete jcasc config if exists and replace with clean template
echo delete jcasc config if exists and replace with clean template
[ -e jcasc-default-config.yaml ] && rm jcasc-default-config.yaml
cp jcasc-default-config.yaml.template jcasc-default-config.yaml

# get the jenkins service account token and update in template
echo get the jenkins service account token and update in template
jenkinstoken=$(kubectl get secret $(kubectl get sa jenkins-admin -n jenkins -o jsonpath='{.secrets[0].name}') -n jenkins -o jsonpath='{.data.token}' | base64 --decode)
sed -i "s|JENKINS-SA-TOKEN|$jenkinstoken|g" jcasc-default-config.yaml

# get the cluster url and update in template
echo get the cluster url and update in template
cluster_url=$(kubectl cluster-info | grep -E 'Kubernetes master|Kubernetes control plane' | awk '/https/ {print $NF}' | sed 's/https\?:\/\///')
sed -i "s|CLUSTERADDRESS|$cluster_url|g" jcasc-default-config.yaml
sed -i "s|\x1b\[[^m]*m||g" jcasc-default-config.yaml

# Configure ArgoCD password
echo "updating ArgoCD password..."
ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d )
argocd login argocd.cluster.clearavenue.com --grpc-web --insecure --username admin --password $ARGOCD_PWD
argocd account update-password --grpc-web --insecure --current-password $ARGOCD_PWD --new-password cL3ar#12

# create and get argocd role token and update in template
echo create and get argocd role token and update in template
argocd login argocd.cluster.clearavenue.com --grpc-web --insecure --username admin --password cL3ar#12
argocd proj role create default jenkins-deploy-role --description "jenkins deploy role"
argocd proj role add-policy default jenkins-deploy-role --action '*' --permission 'allow' --object '*'
roletoken=$(argocd proj role create-token default jenkins-deploy-role | awk '/Token:/ {print $NF}')
sed -i "s|ARGOCD-DEPLOY-ROLE|$roletoken|g" jcasc-default-config.yaml

echo updating jcasc in jenkins
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 apply-configuration < jcasc-default-config.yaml
sleep 10
java -jar jenkins-cli.jar -s https://jenkins.cluster.clearavenue.com -auth jenkins:cL3ar#12 restart

# create a clusterrolebinding for jenkins
echo create a clusterrolebinding for jenkins
kubectl create clusterrolebinding jenkins-cluster-admin --clusterrole=cluster-admin --serviceaccount=jenkins:jenkins --dry-run=client -o yaml | kubectl apply -f -

cd ..

kubectl cluster-info
kubectl config current-context

duration=$(echo "$(date +%s.%N) - $start" | bc)
execution_time=`printf "%.2f seconds" $duration`
echo_header "Script Execution Time: $execution_time"
