
**using the branch fix/grafana-promteheus-upgrade**

```bash
helm repo add mojaloop http://mojaloop.io/helm/repo/

kubectl create ns monitoring

helm -n monitoring upgrade --install promfana ./helm/monitoring/promfana --values=ml-perf-whitepaper-ws/phases/05-monitoring/values.yaml
```
