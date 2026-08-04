# Parameter tuning

Per-scenario tuning lives under the scenario's `overrides/` and
`configmaps/`. The default values in `common/` target a small lab; each
scenario's overrides ratchet up partitions, replicas, JVM heaps, and
connection pools. For adding a new scenario or the full directory layout,
see [benchmarks/README.md](../benchmarks/README.md) (§ Extending, §
Directory layout) and the root [README.md](../README.md#selecting-a-scenario).

## What lives where

| File | Purpose |
|---|---|
| `common/aws.yaml` + the scenario's `overrides/aws.yaml` | AWS instance types, node counts, taint/label maps. Drives both `terraform-apply` and `make k8s`. |
| `common/backend/<version>.yaml` + the scenario's `overrides/backend.yaml` | Kafka broker count, partitions per topic, MySQL innodb settings, MongoDB sizing, Redis settings. |
| `common/mojaloop/<version>.yaml` + the scenario's `overrides/mojaloop.yaml` | Per-service replica counts (handlers, services), log levels, resource requests/limits. |
| the scenario's `overrides/dfsp.yaml` | Per-FSP Helm overlay for the simulators, plus `dfsp_sdk_replicas` / `dfsp_backend_replicas` (ansible vars, not forwarded to Helm — see [architecture.md](architecture.md#dfsps)). |
| the scenario's `configmaps/*.json` | Per-service application config (`default.json` of each service ConfigMap). Patched onto the running ConfigMap by the `switch` role; affected Deployments cycle to pick up changes. |
| `common/k6.yaml` + the scenario's `overrides/k6.yaml` | TPS target, transaction count, FSP pair weights, MSISDN ranges. |

## Rules of thumb

### Kafka

- **Partition count must match the consumer replica count for that topic.**
  Otherwise N replicas can't all consume in parallel and you cap throughput
  at `(actual partitions / N) × per-partition-throughput`. Keep the
  `mojaloop.yaml` override's handler replicas in step with the
  `backend.yaml` override's per-topic partitions.
- **Topic-specific partitioning**: heavy-DB topics (transfer-prepare,
  transfer-fulfil, position-batch) need fewer partitions than
  light-HTTP topics (quotes-post, quotes-put) because the DB is the
  bottleneck. Don't over-partition — empty partitions still cost
  rebalance overhead.
- Single-broker KRaft (replication factor 1) is the default posture for
  a throughput benchmark; it trades HA for no replication overhead. A
  replicated setup costs measurable throughput — treat it as a distinct
  scenario if you need to quantify it.

### MySQL

- For perf runs (no durability requirement), set:
  - `innodb_flush_log_at_trx_commit=2` (sync once per second instead of per txn)
  - `sync_binlog=0` (no fsync on binlog)
  - `log_bin=0` (disable binary log entirely if not replicating)
- These are unsafe in production. Don't copy this setting set into a
  production environment.
- Connection pool sizing: each handler replica × `pool.max` must stay
  under MySQL's `max_connections` — this is a connection-*slot* ceiling,
  not a throughput one, so it can fail at low CPU if under-budgeted.

### Persistence

- **Backend services use `persistence.enabled: false`** (ephemeral
  storage) for throughput. Restarting a Kafka broker loses data —
  intentional for a perf lab.
- A replication-mode scenario (`backend_replication_mode: true` in the
  scenario's `backend.yaml`) makes the `backend` role swap the storage
  class to the Rancher local-path provisioner before installing the chart.

### k6 driver

- At high sustained TPS, OS tuning is required on the k6 + DFSP nodes:
  `ulimit -n 65535`, `net.core.somaxconn=16384`,
  `net.ipv4.ip_local_port_range="1024 65535"`. The Ansible
  cluster-bootstrap playbook (`01-install-microk8s.yml`) applies the
  equivalent sysctls to every switch/DFSP node by default.
