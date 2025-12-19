
## Deploy Mojaloop Backend

Before deploying the Mojaloop switch, all core backend infrastructure components must be installed.  
These include:

- Kafka
- MySQL
- MongoDB
- Redis

These services are deployed using the `example-mojaloop-backend` Helm chart and must be running before Mojaloop workloads are installed.

---

### Set the kubeconfig 

```bash
export KUBECONFIG=ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
```

### Storage Class Adjustment (Required for Kafka/MySQL Replication Mode)

If you intend to run **Kafka or MySQL in replication/persistent mode**, replace the default MicroK8s storage provisioner with Rancher Local Path Provisioner:

```bash
# Remove the default MicroK8s provisioner
kubectl annotate sc microk8s-hostpath storageclass.kubernetes.io/is-default-class-

# Install Rancher local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml

# Set local-path as the default storage class
kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class="true" --overwrite
```

---

### Create Namespace and Image Pull Secret

```bash
kubectl create ns mojaloop

kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=${DOCKERHUB_USERNAME} \
  --docker-password=${DOCKERHUB_TOKEN} \
  --docker-email=${DOCKERHUB_EMAIL} \
  -n mojaloop

kubectl patch serviceaccount default -n mojaloop \
  -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'
```

---

### Deploy Backend Components Using TPS-Specific Override Files

Different performance test scenarios use different backend configurations  
(Kafka brokers, controller layout, partition counts, MySQL replication settings, etc.).

Override files are located in:

```
performance-tests/results/*tps/config-override/backend.yaml
```

#### **500 TPS**
```bash
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/performance-tests/results/500tps/config-override/backend.yaml
```

#### **1000 TPS (single Kafka node)**
```bash
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/performance-tests/results/1000tps/config-override/backend.yaml
```

#### **1000 TPS (Kafka & MySQL replication)**
```bash
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/performance-tests/results/1000tps-replication/config-override/backend.yaml
```

#### **2000 TPS**
```bash
helm -n mojaloop upgrade --install backend mojaloop/example-mojaloop-backend \
  --version 17.1.0 \
  -f ml-perf-whitepaper-ws/performance-tests/results/2000tps/config-override/backend.yaml
```

---

### MySQL Service Alias (Replication Mode Only)

In replication mode, MySQL uses a different service name.  
Apply this alias to avoid changing Mojaloop configuration:

```bash
kubectl apply -f ml-perf-whitepaper-ws/infrastructure/backend/mysqldb-service-alias.yaml
```

---

After the backend is deployed and all pods reach `Running` or `Ready` state, you may proceed to deploying the Mojaloop switch.

### annotation for prometheus
```bash
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/port=9104
# kubectl -n mojaloop annotate pods mysqldb-0 prometheus.io/scrape=true

```