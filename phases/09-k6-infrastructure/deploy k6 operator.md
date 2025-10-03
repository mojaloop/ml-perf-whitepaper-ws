```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator
```


set host in coredns config
```json
    hosts {
      10.110.2.48 account-lookup-service.local quoting-service.local ml-api-adapter.local
      fallthrough
    }
```