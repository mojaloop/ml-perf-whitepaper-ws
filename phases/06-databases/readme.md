
```bash

## Below setup is required only when we want to run kafka and mysql in replication mode.

# remove the default provisioner
kubectl annotate sc microk8s-hostpath storageclass.kubernetes.io/is-default-class-
# Install Rancher local-path provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml
# make the local path provisioner as default
kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class="true" --overwrite


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

## For 500 tps test with 3 kafka brokers and 1 controller(which is overkill)
# helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --version 17.1.0 -f ml-perf-whitepaper-ws/phases/06-databases/override-500.yaml

## For 1000 tps test with a single kafka node ( broker and controller on the same node)
# helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --version 17.1.0 -f ml-perf-whitepaper-ws/phases/06-databases/override-1000.yaml

## For 1000 tps test with replication
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend --version 17.1.0 -f ml-perf-whitepaper-ws/phases/06-databases/override-1000-replication.yaml

## For MySql with replication the service name changes hence create an alias service name so we don't have to change any mojaloop config value
kubectl apply -f ml-perf-whitepaper-ws/phases/06-databases/mysqldb-service-alias.yaml

# # annotation for prometheus
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/port=9104
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/scrape=true



# kubectl run dockerhub-test \
#   --image=docker.io/bitnamilegacy/kafka:3.8.1-debian-12-r0 \
#   --restart=Never \
#   -n mojaloop
```