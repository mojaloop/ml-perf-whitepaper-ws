## Add the common repo

```
helm repo add common https://mojaloop.github.io/charts/repo
helm repo update
helm dep update
```

## Package the simulator helm chart
Run below inside dfsps/mojaloop-simulator
```
helm package . 
```

## Install the simulator helm chart

Make sure you have set KUBECONFIG correctly
```
export KUBECONFIG= deploy/kubeconfigs/ml-perf-perffsp1.yaml

```
Run below from deploy/dfsps directory for each dfsp

```
helm --namespace mojaloop install perffsp1 ./mojaloop-simulator -f ./mojaloop-simulator/values-perffsp1.yaml
helm --namespace mojaloop install perffsp2 ./mojaloop-simulator -f ./mojaloop-simulator/values-perffsp2.yaml
...
```