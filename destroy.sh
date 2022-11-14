# Kill kubectl proxy
pkill kubectl

#Destroy kubernetes objects
kubectl -n default delete po,svc,deployment,rs,secret,configmap --all
kubectl delete namespaces dev stage prod

# Destroy cloud infrastructure created using terraform apply
terraform destroy --auto-approve

rm -rf .terr*
rm terraform.tfstate*
