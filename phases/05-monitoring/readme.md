
**using the branch fix/grafana-promteheus-upgrade**

```bash
helm repo add mojaloop http://mojaloop.io/helm/repo/

kubectl create ns monitoring

kubectl create secret docker-registry dockerhub-secret \
--docker-server=https://index.docker.io/v1/ \
--docker-username=${DOCKERHUB_USERNAME} \
--docker-password=${DOCKERHUB_TOKEN} \
--docker-email=ndelma@gmail.com \
-n monitoring
kubectl patch serviceaccount default \
    -n monitoring \
    -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'


helm -n monitoring upgrade --install promfana ./helm/monitoring/promfana --values=ml-perf-whitepaper-ws/phases/05-monitoring/values.yaml

```
