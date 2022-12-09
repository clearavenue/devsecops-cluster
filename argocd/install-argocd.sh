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
