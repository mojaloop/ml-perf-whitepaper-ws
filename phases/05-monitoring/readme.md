
**using the branch fix/grafana-promteheus-upgrade**

```bash
kubectl crreate ns monitoring

helm repo add mojaloop http://mojaloop.io/helm/repo/
helm -n monitoring upgrade --install promfana ./helm/monitoring/promfana 
```
