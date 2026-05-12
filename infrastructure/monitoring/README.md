## Install monitoring stack from mojaloop helm chart

Checkout mojaloop helm chart repo

```
helm upgrade --install promfana ./monitoring/promfana \
  --namespace monitoring \
  --create-namespace -f ml-perf-whitepaper-ws/infrastructure/monitoring/values.yaml
```

### Access Grafana
```
kubectl port-forward -n monitoring svc/promfana-grafana 3000:80
```
http://localhost:3000

### Access Prometheus
```
kubectl port-forward -n monitoring svc/promfana-kps-prometheus 9090:9090
```
http://localhost:9090

Then in Prometheus go to Status → Targets and see whether your Mojaloop scrape targets are up.

### k6 and prometheus/grafana

To calculate standard deviation in k6 tests we need to use prometheus/grafana.

we enable the remote write receiver in prometheus by enable following in the `values.yaml`

```
  prometheus:
    prometheusSpec:
      enableRemoteWriteReceiver: true # Enable Remote Write Receiver
```
This will enable the remote write receiver URL

```
http://promfana-kps-prometheus.monitoring.svc:9090/api/v1/write
```