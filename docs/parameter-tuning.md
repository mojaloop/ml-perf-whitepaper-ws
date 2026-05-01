# Parameter tuning

Per-scenario tuning lives under `scenarios/<scenario>/overrides/` and
`scenarios/<scenario>/configmaps/`. The default values in `common/`
target a small lab; each scenario's overrides ratchet up partitions,
replicas, JVM heaps, and connection pools.

## What lives where

| File | Purpose |
|---|---|
| `common/aws.yaml` + `scenarios/<x>/overrides/aws.yaml` | AWS instance types, node counts, taint/label maps. Drives both `terraform-apply` and `make k8s`. |
| `common/backend.yaml` + `scenarios/<x>/overrides/backend.yaml` | Kafka broker count, partitions per topic, MySQL innodb settings, MongoDB sizing, Redis settings. |
| `common/mojaloop.yaml` + `scenarios/<x>/overrides/mojaloop.yaml` | Per-service replica counts (handlers, services), log levels, resource requests/limits. |
| `scenarios/<x>/configmaps/*.json` | Per-service application config (`default.json` of each service ConfigMap). Patched onto the running ConfigMap by the `switch` role; affected Deployments cycle to pick up changes. |
| `common/k6.yaml` + `scenarios/<x>/overrides/k6.yaml` | TPS target, transaction count, FSP pair weights, MSISDN ranges. |

## Rules of thumb

The ones learned the hard way during the 500/1000/2000 TPS runs:

### Kafka

- **Partition count must match the consumer replica count for that topic.**
  Otherwise N replicas can't all consume in parallel and you cap throughput
  at `(actual partitions / N) × per-partition-throughput`. The
  `mojaloop.yaml` override for each scenario sets handler replicas in
  step with the `backend.yaml` override's per-topic partitions.
- **Replication factor stays at 1** for single-broker scenarios
  (500tps, 1000tps, 2000tps). Use `1000tps-replication` to exercise
  3-broker replication; expect ~30 % throughput penalty.
- **Topic-specific partitioning**: heavy-DB topics (transfer-prepare,
  transfer-fulfil, position-batch) need fewer partitions than
  light-HTTP topics (quotes-post, quotes-put) because the DB is the
  bottleneck. Don't over-partition — empty partitions still cost
  rebalance overhead.

### MySQL

- For perf runs (no durability requirement), set:
  - `innodb_flush_log_at_trx_commit=2` (sync once per second instead of per txn)
  - `sync_binlog=0` (no fsync on binlog)
  - `log_bin=0` (disable binary log entirely if not replicating)
- These are unsafe in production. Don't copy this scenario set into a
  CC environment.
- Connection pool sizing: each handler replica × `pool.max` must stay
  under MySQL's `max_connections`.

### Persistence

- **Backend services use `persistence.enabled: false`** (ephemeral
  hostPath) for throughput. Restarting a Kafka broker loses data —
  intentional for a perf lab.
- For `1000tps-replication` (the only persistence-on scenario), the
  `backend` role swaps the storage class to Rancher local-path
  provisioner before installing the chart (`backend_replication_mode: true`
  in the scenario's `backend.yaml`).

### k6 driver

- For 2000 TPS+, OS tuning is required on the k6 + DFSP nodes:
  - `ulimit -n 65535`
  - `net.core.somaxconn=16384`
  - `net.ipv4.ip_local_port_range="1024 65535"`
- The Ansible cluster-bootstrap playbooks already set these on
  `k6_node_class` + `dfsp_node_class` nodes in the 2000tps scenario.

## How to add a new scenario

1. Create the directory structure:
   ```
   scenarios/myscenario/
     overrides/aws.yaml          # (optional) infra topology diff
     overrides/backend.yaml       # Kafka/MySQL tuning diff
     overrides/mojaloop.yaml      # replica count diff
     overrides/k6.yaml            # (optional) k6 driver diff
     configmaps/<svc>-config.json # (optional) per-service config diff
     .env                          # secrets (gitignored)
   ```
2. Each override file is a partial helm values diff — only the keys
   you're changing. The role merges it on top of `common/<chart>.yaml`
   via `helm -f common/<chart>.yaml -f scenarios/<x>/overrides/<chart>.yaml`.
3. Run `make terraform-apply SCENARIO=myscenario`, then the rest of
   the chain.

## Reference: what each shipped scenario tuned

The four shipped scenarios (`500tps`, `1000tps`, `1000tps-replication`,
`2000tps`) each have their `overrides/` and `configmaps/` directories
preserving the exact settings used for the white paper runs. Read them
top-to-bottom — they are the closest thing to a parameter-tuning
recipe.

The deltas roughly scale as:

| Scenario | Handler replicas (each) | Topic partitions | Kafka brokers | MySQL workers |
|---|---|---|---|---|
| 500tps  | 12 | 12 | 1 | 32 |
| 1000tps | 18-24 | 24 | 1 | 48 |
| 2000tps | 32-48 | 32 | 1 | 64 |
| 1000tps-replication | 18-24 | 24 | 3 (RF=2) | 48 |

(See the scenario YAMLs for exact values — these numbers are
indicative.)
