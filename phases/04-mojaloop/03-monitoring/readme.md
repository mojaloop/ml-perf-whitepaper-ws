

```bash
# Set the helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create the monitoring ns
kubectl create namespace monitoring

# Deployment the stack
helm upgrade --install promstack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f values.yaml


kubectl --namespace monitoring get secrets promstack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo


# # set the DNS record in the local computer host grafana.local
# # then forward ingress port
# kubectl port-forward -n ingress daemonset/nginx-ingress-microk8s-controller 80:80 443:443 --address 0.0.0.0


```