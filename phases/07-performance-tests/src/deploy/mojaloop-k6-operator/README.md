
## Install k6 Operator Once
### Add Grafana Helm repository
```
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```
### Install k6 Operator
```
helm install k6-operator grafana/k6-operator --version 3.13.1 --namespace k6-operator-system --create-namespace
```
## Add Grafana Helm Repository:
```
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```
<!-- 
# Run the tests

## Package the Helm Chart
```
cd mojaloop-k6-operator
helm dependency build
helm package .
```

## Deploy the Chart
```
helm install moja-k6-test ./mojaloop-k6-operator-0.1.0.tgz --namespace k6-tests --set parallelism=1
```

## Monitor the Test
```
kubectl get testruns -n k6-tests
kubectl get pods -n k6-tests
kubectl logs -n k6-tests -l app.kubernetes.io/managed-by=k6-operator
``` -->