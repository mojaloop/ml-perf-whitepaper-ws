```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator
```


set host in coredns config
```json
        hosts {
          10.112.2.141 sim-fsp201.local
          10.112.2.41 sim-fsp202.local
          10.112.2.235 sim-fsp203.local
          10.112.2.37 sim-fsp204.local
          10.112.2.71 sim-fsp205.local
          10.112.2.246 sim-fsp206.local
          10.112.2.109 sim-fsp207.local
          10.112.2.116 sim-fsp208.local
          fallthrough
        }
```