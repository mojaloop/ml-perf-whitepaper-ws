
```bash
# we are currently using the example backend. This must be changed to allow proper monitoring and performance optimizations

kubectl create ns mojaloop


kubectl create secret docker-registry dockerhub-secret \
--docker-server=https://index.docker.io/v1/ \
--docker-username=${DOCKERHUB_USERNAME} \
--docker-password=${DOCKERHUB_TOKEN} \
--docker-email=ndelma@gmail.com \
-n mojaloop

kubectl patch serviceaccount default \
    -n mojaloop \
    -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'


helm -n mojaloop install backend mojaloop/example-mojaloop-backend --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/06-databases/values.yaml

# # annotation for prometheus
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/port=9104
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/scrape=true

```