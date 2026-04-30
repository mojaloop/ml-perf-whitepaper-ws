# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Mojaloop Performance Testing Workstream repository — a complete, reproducible workspace for benchmarking the Mojaloop financial switch at scale (500–2000 TPS, 1M transfers per run). It provisions AWS infrastructure, deploys isolated MicroK8s clusters, and runs k6-based load tests across multiple DFSP simulators.

## Build and Run Commands

### Infrastructure Provisioning (Terraform)

```bash
cd infrastructure/provisioning/terraform
make init       # terraform init
make plan       # terraform plan → artifacts/terraform.plan
make apply      # terraform apply artifacts/terraform.plan
make destroy    # terraform destroy
make show       # terraform show state
make fmt        # terraform fmt
```

State is stored locally at `infrastructure/provisioning/artifacts/terraform.tfstate`. Terraform generates `inventory.yaml`, `ssh-config`, `hosts`, and `connection-info.txt` into `../artifacts/`.

### Kubernetes Cluster Setup (Ansible)

```bash
cd infrastructure/kubernetes/ansible
make deploy          # Run all 4 playbooks
make install         # 01: Install MicroK8s on all nodes
make switch-cluster  # 02: Form 3-node HA switch cluster with labels/taints
make fsp-clusters    # 03: Configure DFSP single-node clusters
make kubeconfig      # 04: Generate kubeconfigs with SSH ProxyCommand
make ping            # Connectivity test
make status          # kubectl get nodes on all clusters
```

### Cluster Access (all kubectl/helm commands)

All private clusters require a SOCKS5 proxy through the bastion:

```bash
ssh -D 1080 perf-jump-host -N &
export HTTPS_PROXY=socks5://127.0.0.1:1080
export KUBECONFIG=infrastructure/provisioning/artifacts/kubeconfigs/kubeconfig-mojaloop-switch.yaml
```

### Running Performance Tests

```bash
cd performance-tests/src/scripts
./trigger-tests.sh
```

This uninstalls any previous `k6-test-mojaloop` Helm release, then deploys the `mojaloop-k6-operator` Helm chart which creates a k6 `TestRun` CR. Monitor with:

```bash
kubectl --kubeconfig ...kubeconfig-k6.yaml get pods -n k6-test
kubectl --kubeconfig ...kubeconfig-k6.yaml logs -n k6-test <pod> -f
```

### Pre-test Data Setup

Before running tests, deploy a curl pod in the k6 cluster, then:

1. `performance-tests/src/utils/register-msisdnOracle-on-sim.sh` — registers MSISDNs on each DFSP simulator
2. `performance-tests/src/utils/insert-msisdnOracle.sh` — inserts MSISDNs into `oracle_msisdn` MySQL database

## Architecture

### Cluster Topology

Three isolated MicroK8s cluster groups on a single AWS VPC (`10.112.0.0/16`), all in a private subnet behind a bastion:

- **Switch cluster** (3-node HA): Mojaloop core services, Kafka, MySQL, MongoDB, Redis, monitoring. Internal NLB on ports 80→30080, 443→30443 targeting the 3 generic nodes.
- **DFSP clusters** (8x single-node): `fsp201`–`fsp208`, each running `mojaloop-simulator` + `sdk-scheme-adapter`.
- **k6 cluster** (1 node): k6 Operator + test runner pods.

### Cross-Cluster DNS

Since clusters are isolated on a private VPC with `.local` domains, DNS is wired by patching CoreDNS ConfigMaps and Kubernetes `hostAliases`:

- k6 cluster CoreDNS: `sim-fsp201.local` → DFSP node IPs
- DFSP CoreDNS + hostAliases: `account-lookup-service.local`, `quoting-service.local`, `ml-api-adapter.local` → switch NLB IP
- Switch hostAliases: `sim-fspNNN.local` → DFSP node IPs (patched on ALS, Quoting, ML-API-Adapter, TTK deployments)

### Node Scheduling

Dedicated nodes use taints + node labels (workload classes) to isolate Kafka, MySQL, and monitoring from application workloads. Labels like `workload-class.mojaloop.io/KAFKA-DATA-PLANE`, `RDBMS-CENTRAL-LEDGER-LIVE` control pod placement.

### k6 Test Flow

The k6 script (`performance-tests/src/mojaloop-k6-operator/scripts/tests.js`) uses `constant-arrival-rate` executor and runs the full FSPIOP lifecycle per iteration:

1. **Discovery**: `GET /parties/MSISDN/{msisdn}` via source DFSP SDK
2. **Quote**: `POST /quotes` via source DFSP SDK
3. **Transfer**: `POST /simpleTransfers` with ILP packet from quote

FSP pairs are configurable with weights in `performance-tests/src/values/values.yaml`.

## Key Configuration Files

| File | Purpose |
|------|---------|
| `infrastructure/provisioning/config.yaml` | Master config: AWS region, instance types, node labels/taints, K8s version, NLB |
| `performance-tests/src/values/values.yaml` | Test parameters: TPS target, transaction count, FSP pairs, MSISDN ranges |
| `performance-tests/results/<scenario>/config-override/backend.yaml` | Per-TPS Kafka/MySQL tuning (partitions, replication, memory) |
| `performance-tests/results/<scenario>/config-override/mojaloop-values.yaml` | Per-TPS service replica counts and log levels |
| `performance-tests/results/<scenario>/configmaps/*.json` | Exact service configmap contents used for each TPS run |
| `infrastructure/dfsp/deploy.bash` | Deploys all 8 DFSP simulators (update `SWITCH_IP` and `REPLICAS` before running) |

## Deployment Sequence

After Terraform + Ansible provisioning:

1. **cert-manager** — `infrastructure/certmanager/` (Helm install + ClusterIssuers)
2. **Monitoring** — `infrastructure/monitoring/` (Prometheus + Grafana via promfana chart)
3. **Backend** — `infrastructure/backend/` (Kafka, MySQL, MongoDB, Redis via `mojaloop/example-mojaloop-backend`)
4. **Mojaloop switch** — `infrastructure/mojaloop/` (via `mojaloop/mojaloop` Helm chart + per-TPS overrides + hostAliases patches)
5. **DFSP simulators** — `infrastructure/dfsp/deploy.bash` (loop over fsp201–fsp208, deploy sims + patch DNS)
6. **k6 infrastructure** — `infrastructure/k6-infrastructure/setup-k6-infra.bash` (k6 Operator + CoreDNS patches)
7. **DFSP onboarding** — via Testing Toolkit at `http://testing-toolkit.local/admin/outbound_request`
8. **MSISDN registration** — `performance-tests/src/utils/` scripts
9. **Test execution** — `performance-tests/src/scripts/trigger-tests.sh`

## Performance Tuning Notes

- Backend services use `persistence.enabled: false` (ephemeral storage) for throughput
- MySQL uses aggressive settings: `innodb_flush_log_at_trx_commit=2`, `sync_binlog=0`, `log_bin=0`
- For 2000 TPS: OS tuning required on k6/DFSP nodes (`ulimit -n 65535`, `somaxconn=16384`, port range `1024-65535`)
- Kafka partition counts must match handler replica counts (e.g., `topic-notification-event` partitions = notification handler replicas)
- The `results/` directories preserve exact configs and results for 500, 1000, 1000-replication, and 2000 TPS scenarios as reference
