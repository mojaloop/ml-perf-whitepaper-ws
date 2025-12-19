# Deploy k6 Infrastructure

This step installs the **k6 Operator** in the dedicated **k6 Kubernetes cluster**. The k6 cluster centrally generates load and sends traffic to the DFSP simulator endpoints.

The recommended approach is to use the bootstrap script below, which sets kubeconfig, prepares the namespace, configures Docker image pull secrets, installs the k6 Operator, and configures CoreDNS so the k6 cluster can resolve DFSP simulator domains.

---

## Quick Start (Recommended)

```bash
./ml-perf-whitepaper-ws/infrastructure/k6-infrastructure/setup-k6-infra.bash
```

---

## What the Script Does

1. Sets `KUBECONFIG` to the k6 cluster kubeconfig:
   `ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-k6.yaml`
2. Creates namespace `k6-test`
3. Creates/updates a Docker Hub pull secret (`dockerhub-secret`) in `k6-test`
4. Patches the `default` ServiceAccount in `k6-test` to use the pull secret
5. Installs (or upgrades) the `grafana/k6-operator` Helm chart into `k6-test`
6. Patches CoreDNS to resolve DFSP simulator domains:
   `sim-fsp201.local` ... `sim-fsp208.local`
7. Restarts CoreDNS

---


## How DFSP IPs Are Resolved

The script automatically derives the DFSP VM IP addresses from the Terraform-generated SSH config:

```
ml-perf-whitepaper-ws/infrastructure/provisioning/artifacts/ssh_config
```

It then patches CoreDNS in the k6 cluster with a `hosts` block similar to:

```text
hosts {
  10.112.2.132 sim-fsp201.local
  10.112.2.103 sim-fsp202.local
  10.112.2.59  sim-fsp203.local
  10.112.2.150 sim-fsp204.local
  10.112.2.53  sim-fsp205.local
  10.112.2.219 sim-fsp206.local
  10.112.2.244 sim-fsp207.local
  10.112.2.172 sim-fsp208.local
  fallthrough
}
```
---

## Manual Installation (Optional)

If you prefer to install the operator manually:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator -n k6-operator --create-namespace
```

Then update CoreDNS in the k6 cluster to resolve `sim-fsp*.local` and restart CoreDNS:

```bash
kubectl -n kube-system edit configmap coredns
kubectl -n kube-system rollout restart deployment coredns
```
