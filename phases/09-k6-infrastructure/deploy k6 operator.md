```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator
```


set host in coredns config
```json
        hosts {
          10.112.2.132 sim-fsp201.local
          10.112.2.103 sim-fsp202.local
          10.112.2.59 sim-fsp203.local
          10.112.2.150 sim-fsp204.local
          10.112.2.53 sim-fsp205.local
          10.112.2.219 sim-fsp206.local
          10.112.2.244 sim-fsp207.local
          10.112.2.172 sim-fsp208.local
          fallthrough
        }
```