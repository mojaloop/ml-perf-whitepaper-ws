
```bash
# we are currently using the example backend. This must be changed to allow proper monitoring and performance optimizations

kubectl create ns mojaloop

helm -n mojaloop install backend mojaloop/example-mojaloop-backend --version 17.1.0 --values=ml-perf-whitepaper-ws/phases/06-databases/values.yaml

# annotation for prometheus
kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/port=9104
kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/scrape=true

```