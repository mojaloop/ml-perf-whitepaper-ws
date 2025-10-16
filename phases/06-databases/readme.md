
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


# helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --version 17.1.0 -f ml-perf-whitepaper-ws/phases/06-databases/values.yaml -f ml-perf-whitepaper-ws/phases/06-databases/override-200.yaml

helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --version 17.1.0 -f ml-perf-whitepaper-ws/phases/06-databases/override-500.yaml

# # annotation for prometheus
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/port=9104
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/scrape=true



# kubectl run dockerhub-test \
#   --image=docker.io/bitnamilegacy/kafka:3.8.1-debian-12-r0 \
#   --restart=Never \
#   -n mojaloop
```