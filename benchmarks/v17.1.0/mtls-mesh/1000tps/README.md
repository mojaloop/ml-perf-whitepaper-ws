# v17.1.0 / mtls-mesh / 1000tps — Scenario Report

Status: **PASS** — 3,599,479 transfers measured at 1000 TPS over a full
one-hour steady window, steady-state e2e p99 **996 ms** against the `<1s`
goal, with the Kafka validity gate passing and semi-sync replication engaged
at zero fallbacks.

This scenario runs the mtls-mesh security posture (Istio ambient service
mesh + Kafka/MySQL protocol TLS) at 1000 TPS with real Kafka/MySQL
replication and a production-readiness pass informed by ISO 27001 Annex A
technical controls (data-at-rest encryption, real persistence) — and there
is no durability concession behind the result. MySQL runs full per-commit
durability (`sync_binlog=1`, `innodb_flush_log_at_trx_commit=1`), with every
committed transaction acknowledged by the replica before the client sees it
and zero fallbacks to asynchronous across the run. Kafka runs RF=3 with
`min.insync.replicas=2` (majority quorum — tolerates one broker down
without halting writes) and `request.required.acks=all` on every producer
on the transfer, quote, and notification paths, so a message is
acknowledged only once every broker in the current in-sync-replica set has
it, not just the leader.

## 1. Scenario

- **Version:** v17.1.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 1000 TPS, 13 FSP pairs (4 source FSPs → 4 destination FSPs)
- **Status:** ✅ **PASS** — steady-state e2e p99 996 ms over a 3600 s window, semi-sync replication engaged at zero fallbacks, `sync_binlog=1`

## 2. Test methodology & definitions

- **Steady-state window:** start+5 min .. end−2 min (TPC/SPEC-style warm-up/drain trim), applied mechanically by `benchmarks/tools/steady-state.sh` — no window selection by judgement. `targetTxnCount` is sized so the steady window is exactly 3,600 s after the fixed 5-min/2-min trim.
- **The k6 end-of-run summary is the full-run aggregate** and includes the run's first and last minutes; steady-state is the authoritative number for pass/fail. On this run they read 981 ms full-run and 996 ms steady-state.
- **Latency falls over the first minutes of a run**, which is what the warm-up trim exists to exclude.
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0, position-batch/prepare ≈ 2.0. A failing gate means the pipeline was not keeping up, and invalidates the percentiles regardless of what they read.

## 3. Test design parameters

- **Target TPS:** 1000
- **Target transaction count:** 4,020,000 (`overrides/k6.yaml` `targetTxnCount`) — run length is `targetTxnCount / targetTps` with no ramp, so 4,020 s of load leaves exactly 3,600 s in the steady window after the fixed 5-min warm-up / 2-min drain trim
- **Transfer amount / currency:** 1 XXX
- **Test load distribution** `overrides/k6.yaml`:

| Source (Payer) | → fsp202 | → fsp204 | → fsp206 | → fsp208 | Total generated |
|---|---|---|---|---|---|
| fsp201 (large) | 49% | 7% | 7% | 7% | **70%** |
| fsp203 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| fsp205 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| fsp207 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| **Total received** | **49%** | **17%** | **17%** | **17%** | **100%** |

## 4. Hardware / infrastructure

- **This scenario has its own dedicated Terraform workspace**
  (`v17.1.0-mtls-mesh-1000tps`) with persistent storage throughout — MySQL
  and Kafka both run on real EBS-backed volumes, not ephemeral disk.

| Role | Count | Instance type | Root storage | Notes |
|---|---|---|---|---|
| Switch (generic) | 10 | m7i.2xlarge (8 vCPU/32GiB) | 128GB gp3 | sw1-n1..n10 |
| Kafka | 3 | m7i.2xlarge (8 vCPU/32GiB) | 200GB gp3 | sw1-kafka-n1..n3, combined KRaft controller+broker; data on a separate 200GB gp3 PV per broker |
| MySQL | 2 | m7i.2xlarge (8 vCPU/32GiB) | 200GB gp3 | sw1-mysql-n1 (primary), sw1-mysql-n2 (secondary); data on a separate 100GB io2 PV per node at 10,000 provisioned IOPS |
| Monitoring | 1 | m6i.large | 256GB gp3, 10,000 IOPS | |
| DFSP fsp201, fsp202 | 2 | c7i.8xlarge (32 vCPU/64GiB) | 128GB gp3 | primary traffic-generating FSPs (70% + 49% combined weight) |
| DFSP fsp203-208 | 6 | c7i.2xlarge (8 vCPU/16GiB) | 128GB gp3 | |
| k6 | 1 | m7i.2xlarge (8 vCPU/32GiB) | 128GB gp3 | |
| Bastion | 1 | t3.small | 16GB gp3 | |

- **AZ / placement:** eu-west-2b, cluster placement group (lowest inter-node latency)
- **Switch generic nodes (10 × m7i.2xlarge):** Mojaloop's Node.js services show no evident cluster/worker_threads use, so a pod is effectively a 1-vCPU consumer regardless of node size — more nodes at the same size gives finer bin-packing granularity than fewer larger ones.
- **Kafka (3 × m7i.2xlarge):** RF=3 requires at least 3 distinct brokers, and Raft controller quorum needs an odd node count for majority fault tolerance.
- **MySQL (2 × m7i.2xlarge, both nodes):** sized for the durability settings' CPU cost (binlog construction, per-commit fsync, semi-sync ack handling) on top of baseline transaction throughput.

### Cluster architecture (MicroK8s)

10 isolated MicroK8s clusters (v1.32/stable) on one AWS VPC, private subnet,
each with its own control plane.

**Switch cluster** (`mojaloop-switch`, 16 nodes: sw1-n1..n10, 3 kafka, 2 mysql, monitoring)
- Runs Mojaloop core services, Kafka (3-broker), MySQL (primary+secondary), Prometheus/Grafana.
- All 16 nodes are full MicroK8s/dqlite members. Workload placement is enforced by node taints/labels.

**DFSP clusters** (`fsp201`..`fsp208`, 1 node each) and **k6 cluster** (1 node): each an independent single-node MicroK8s cluster with no shared control plane.

## 5. System-level overrides

- **Kernel pin:** `6.17.0-1013-aws` on switch nodes — the stock AMI kernel shows ~10% higher softirq under sustained load.
- **Node taints/labels:** `workload-class.mojaloop.io/*` partitioning across the 10 generic nodes. Kafka nodes (3) tainted `dedicated=kafka:NoSchedule`; MySQL nodes (2) tainted `dedicated=mysql:NoSchedule`.
- **CNI:** Cilium eBPF (native routing, kube-proxy replacement), replacing MicroK8s' default Calico dataplane.

## 6. Helm chart versions + values overrides

- **Chart versions:** mojaloop=17.1.0, backend=17.1.0, simulator=15.10.0
- **Key overrides:**
  - `overrides/mojaloop.yaml` — replica counts (below)
  - `overrides/backend.yaml` — Kafka RF=3 with `min.insync.replicas=2` across 3 brokers on gp3, MySQL primary+secondary with semi-sync + durable commits on io2
  - `overrides/aws.yaml` — node sizing — **dedicated infra, not shared**
  - `overrides/k6.yaml` — 1000 TPS target, 4,020,000 transaction count

## 7. Pod distribution & replica counts

`account-lookup-service` has no Kafka-partition constraint and is sized as
a clean multiple of the 10-node generic switch cluster (3 pods per node, no
remainder for topologySpread to arbitrate). `ml-api-adapter-handler-notification`
lands on the same multiple by a different route — its topic's partition
count (`topic-notification-event` = 30) was sized to a multiple of 10, and
its replica count follows that 1:1. Every other service in this table is
either Kafka-consumer-constrained at a different partition count or sized
independently with no regard to node count.

Consumer replica counts are matched **1:1 to their topic's partition count**
— Kafka consumer-group parallelism can never exceed partition count, so
replicas above that number sit permanently idle.

| Service | Replicas | Matching topic partitions |
|---|---|---|
| account-lookup-service | 30 | — |
| als-msisdn-oracle | 10 | — |
| centralledger-service | 2 | — |
| centralledger-handler-transfer-prepare | 12 | `topic-transfer-prepare` = 12 |
| centralledger-handler-transfer-fulfil | 12 | `topic-transfer-fulfil` = 12 |
| handler-pos-batch (transfer-position-batch) | 8 | `topic-transfer-position-batch` = 8 |
| quoting-service | 12 | `topic-quotes-post`/`-put` = 12 |
| quoting-service-handler | 12 | |
| ml-api-adapter-service | 12 | — |
| ml-api-adapter-handler-notification | 30 | `topic-notification-event` = 30 |
| kafka-controller | 3 (StatefulSet, combined controller+broker) | |
| mysqldb | primary + 1 secondary (StatefulSet) | |

`centralledger-service` sits off the transfer hot path — it backs occasional
participant-endpoint lookups from the notification handler and
account-lookup-service, a few requests a second at this TPS, and is not
partition- or consumer-parallelism bound. It measures 0.013 cores per pod under
load, so 2 replicas are sized for availability rather than throughput.

Off-path singletons (centralledger-handler-timeout/get/admin-transfer,
centralsettlement-*, transaction-requests-service, TTK backend/frontend)
unchanged at 1 replica each — no load-scaling need.

**DFSP simulators**: `dfsp_backend_replicas_default: 1`, except fsp202 at 4,
where measured backend CPU load justifies it (`overrides/dfsp.yaml`).

## 8. Security setup (detailed)

Three independently layered mechanisms are active: edge mTLS between each DFSP
and the switch, Istio ambient mesh (ztunnel HBONE) between switch workloads,
and protocol TLS on the Kafka and MySQL connections. Crypto is ECDSA P-256
throughout — a shared lab CA and leaf at the edge (`certs/regen-certs.sh`),
istiod-issued per-workload SPIFFE certs inside the mesh
(`ECC_SIGNATURE_ALGORITHM=ECDSA` in `common/istiod-values.yaml`). TLS floor
1.2, 1.3 auto-negotiated.

**DFSP-side mTLS is terminated by an Istio sidecar and gateway, not by the
scheme-adapter.** Each `fspNNN` cluster runs its own istiod (they are
independent single-node MicroK8s clusters with no cross-cluster path to a
shared control plane), an inbound Gateway, and an outbound sidecar on the
scheme-adapter. This replaces the application's inbuilt TLS on both sides:
nginx SSL-passthrough on the inbound path and the app's own `https.Agent` on
the outbound path. Passthrough was replaced because it pins a whole client
connection to a single scheme-adapter pod for the connection's lifetime, so
long-lived keep-alive connections from the switch concentrate on one pod
instead of spreading across replicas. Terminating at the sidecar lets Envoy
load-balance per request. Role: `ansible/roles/istio_dfsp`, applied before
`mtls_dfsp` disables the app's own TLS.

**Prometheus scrape exemption.** A selector-scoped PeerAuthentication permits
plaintext on nine application ports (3000-3003, 3007, 4000-4002, 6060) for the
`moja` release. Ambient enrollment under a namespace-wide STRICT policy
otherwise rejects Prometheus scrapes of ambient-only pods, silently: load
continues to run while every switch-side handler histogram disappears.
Enrolled-to-enrolled traffic still negotiates mTLS — PERMISSIVE only admits a
plaintext fallback, and measurement confirms application traffic is using it:
7731 mutual-TLS requests/s against 2/s plaintext. The exemption is a real
relaxation of the posture on those ports and is stated wherever this result is
cited. `portLevelMtls` requires a selector, so the exemption ships as its own
selector-scoped policy rather than on the namespace default, and that policy
restates `mtls.mode: STRICT` because a selector-scoped policy replaces the
namespace default rather than merging with it.

**Kafka controller/interbroker traffic is mTLS-encrypted.** At 3 brokers,
Raft consensus and replication traffic crosses the pod network between 3
separate nodes, and Kafka pods are deliberately excluded from the ambient
mesh (to avoid double-encrypting the client-facing SSL stream), so they get
no mTLS from that layer either. Both listeners run
`protocol: SSL` with `sslClientAuth: required` (real mutual TLS, not the
client listener's encrypt-only posture) — this traffic is exclusively
broker↔broker and broker↔controller-quorum, all mutually trusted, with none
of the external-client compatibility concern that drove the client
listener's `none` setting. The auto-generated PEM cert covers all
SSL-enabled listeners per-pod.

## 9. Kafka / MySQL performance tuning

**Kafka** (3-broker combined KRaft controller+broker, RF=3, `min.insync.replicas=2`):
- Listener: SSL-only on port 9092 (client + external). Controller/interbroker: SSL with required mTLS.
- `min.insync.replicas=2` (majority quorum — tolerates 1 broker down without halting writes), set in the top-level `kafka.extraConfig`.
- Partition counts (matching consumer replica counts): `topic-transfer-prepare`=12, `topic-transfer-fulfil`=12, `topic-notification-event`=30, `topic-transfer-position-batch`=8, `topic-quotes-post`/`-put`=12 each.
- Persistence: gp3 (not io2) EBS-backed PV, 200GB/broker — decided over io2 because Kafka's I/O is predominantly sequential (append-only log, replication fetch/append), which fits gp3's bundled throughput rather than io2's per-IOPS pricing. Depends on the `ebs-gp3-encrypted` StorageClass installed by `make ebs-csi`.
- Resources: 5/7 vCPU request/limit, 12/24Gi memory request/limit per broker on m7i.2xlarge

**MySQL** (primary + 1 secondary, semi-sync replication):
- `architecture: replication`, semi-sync (`rpl_semi_sync_source`/`rpl_semi_sync_replica` plugins loaded via `--plugin-load-add`) — the primary blocks for the secondary's acknowledgement before committing.
- **Full per-commit durability**: `sync_binlog=1` with `innodb_flush_log_at_trx_commit=1` and `innodb_doublewrite=1`. Both the engine and the binary log are durable per transaction, so the binlog is a valid point-in-time-recovery source and a crash-recovered primary cannot be behind its own replica.
- **The secondary runs `sync_binlog=1000`, not the primary's `sync_binlog=1`.** MySQL can batch several transactions' binlog writes into one disk fsync instead of paying the fsync cost per transaction ("group commit") — on the primary, concurrent client commits do this naturally, averaging ~7 transactions per fsync. The replica can't: `replica_preserve_commit_order=ON` forces its applier to commit one transaction at a time in the primary's exact order, so nothing ever arrives concurrently to batch, and every commit would pay its own fsync. At the primary's `sync_binlog=1`, that caps the replica's replay rate at roughly half the primary's commit rate — with lag growing without bound instead of staying near zero.
- Persistence: io2 at 10,000 provisioned IOPS, 100 GB/node — MySQL's commit path is frequent small synchronous writes, which is the profile io2 exists for and what makes `sync_binlog=1` affordable. Measured use is 3,249 write IOPS, 33% of provisioned.
- Resources: 6/7 vCPU request/limit, 22/28Gi memory request/limit per node on m7i.2xlarge.
- Secondary is sized **identically** to primary, not smaller — semi-sync means an undersized secondary throttles the primary's commit latency too, not just its own capacity.

Every MySQL setting and its rationale is tabulated below.

### MySQL settings reference

All values from `overrides/backend.yaml`. Settings marked **hardware-derived**
must be rescaled to the target environment rather than copied — they are
derived from this deployment's instance size and volume provisioning, not from
a rule that travels.

**Durability and recovery**

| Setting | Value | Purpose |
|---|---|---|
| `innodb_flush_log_at_trx_commit` | 1 | Fsync the InnoDB redo log on every commit. This is what makes a committed transfer survive a crash; not a throughput knob. |
| `sync_binlog` | 1 (primary) / 1000 (secondary) | Fsync the binary log per commit on the primary — required for PITR and to keep a crash-recovered primary's GTID set consistent with what replicas applied. Relaxed on the secondary; see the replication note above. |
| `innodb_doublewrite` | 1 | Protects against torn pages on crash. |
| `innodb_rollback_on_timeout` | ON | At MySQL's default (OFF) a lock-wait timeout rolls back only the timed-out *statement*, leaving the transaction open — an application treating the error as a failed transaction can then commit a partial one. |
| `binlog_expire_logs_seconds` | 14400 | Test-environment disk constraint, **not a production value**. It bounds how long the secondary may be offline before the primary purges binlogs it still needs, after which replication cannot resume without a re-seed. |

**Replication**

| Setting | Value | Purpose |
|---|---|---|
| `gtid_mode` / `enforce_gtid_consistency` | ON | Global transaction IDs — reliable replica positioning and safe promotion. |
| `binlog_format` | ROW | Required for semi-sync correctness and for the parallel applier. |
| `log_replica_updates` | ON (default) | The secondary writes its own binlog, so it is promotable and can chain. |
| `rpl_semi_sync_source_enabled` | ON | Primary waits for replica acknowledgement before committing. Acknowledgement is on relay-log *receipt*, so apply lag never costs committed data. |
| `rpl_semi_sync_source_timeout` | 1000 ms | Bounds the commit stall when the replica is unresponsive before falling back to asynchronous. MySQL's 10,000 ms default exceeds the entire e2e budget by 10×; 1,000 ms sits three orders of magnitude above the measured 0.6 ms acknowledgement so it never fires spuriously. |
| `rpl_semi_sync_source_wait_for_replica_count` | 1 | Number of acknowledgements required. With a second replica added this stays at 1, which *reduces* tail latency — the primary proceeds on whichever acknowledges first. |
| `replica_parallel_type` | LOGICAL_CLOCK | Enables parallel apply on the replica. |
| `replica_parallel_workers` | 7 | **Hardware-derived** — sized to the secondary's core count. |
| `replica_preserve_commit_order` | ON (default) | Replica commits in the primary's original order. Keep it: without it the replica can transiently expose a state the primary never held. It is also why the secondary needs the relaxed `sync_binlog`. |
| `relay_log_recovery` | ON | Makes the replica crash-safe. The semi-sync acknowledgement means the event reached the relay log, but `sync_relay_log` defaults to 10000 so that write is only fsynced periodically; without recovery the replica resumes from a relay log missing acknowledged events and never refetches them. |
| `read_only` | ON (secondary) | Blocks direct writes from ordinary application connections. `super_read_only` is deliberately **not** set: the bitnami entrypoint runs a housekeeping `DELETE FROM mysql.user` as root during bootstrap, `super_read_only` blocks it even for SUPER-privileged connections, and the secondary aborts before replication is configured. |

**Memory and I/O**

| Setting | Value | Purpose |
|---|---|---|
| `innodb_buffer_pool_size` | 8G | **Hardware-derived.** 29% of the container limit here; conventional sizing for a dedicated host is 50–70% of available memory. Ample for this dataset — physical reads measured at 0/s against 21.5k queries/s. |
| `innodb_buffer_pool_instances` | 8 | Reduces pool mutex contention; scales with pool size. |
| `innodb_redo_log_capacity` | 2G | Generous, to avoid checkpoint stalls. Confirmed sufficient: zero `Innodb_log_waits` under load. |
| `innodb_log_buffer_size` | 256M | Avoids flushing the log buffer mid-transaction. |
| `innodb_flush_method` | O_DIRECT | Bypasses the OS page cache, which would otherwise double-buffer against the InnoDB pool. |
| `innodb_io_capacity` / `_max` | 5000 / 10000 | **Hardware-derived** from the volume's provisioned IOPS, not from measured demand — dirty pages stay below `innodb_max_dirty_pages_pct_lwm`, so neither value is reached. `io_capacity` is the background-flush budget, `_max` the burst ceiling under checkpoint pressure. Telling InnoDB the device sustains more than it does produces checkpoint stalls that look nothing like an I/O problem. |
| `innodb_read_io_threads` / `_write_io_threads` | 8 / 8 | **Hardware-derived** — background I/O parallelism. |
| `tmp_table_size` / `max_heap_table_size` | 256M | Keeps intermediate results in memory. Note this is a per-connection ceiling, so it multiplies against the connection count. |

**Concurrency**

| Setting | Value | Purpose |
|---|---|---|
| `max_connections` | 6000 | **Hardware-derived**, sized against this deployment's summed application pool configuration (~4,500) rather than measured peak (927). Deliberately generous: a connection-slot ceiling fails hard and abruptly rather than degrading, and unused slots cost nothing — the only measurable price is performance_schema autosizing (626 MB total). |
| `thread_cache_size` | 200 | Avoids thread creation cost on reconnect churn. |
| `table_open_cache` / `table_definition_cache` | 8000 / 4000 | Sized alongside `max_connections`; zero cache overflows observed. |
| `lock_wait_timeout` | 60 | **Metadata** locks (DDL), not row locks. MySQL's default of one year turns a schema change that cannot get its lock into an indefinite stall, and because later queries on that table queue behind the pending request, a blocked migration takes the table down rather than merely failing. |
| `innodb_lock_wait_timeout` | 50 (default) | **Row** locks — deliberately left at the default. The objective is a percentile, not a per-transaction deadline: lowering it does not reduce contention, it converts transfers that would have completed into failures. Mojaloop also carries its own expiry mechanism, and a database timeout firing first would preempt it with a raw InnoDB error instead of a proper FSPIOP expiry. |
| `skip_name_resolve` | ON | Skips reverse DNS on connect. |

**Diagnostics**

| Setting | Value | Purpose |
|---|---|---|
| `performance_schema` | ON | Kept on: `events_statements_summary_by_digest` is the only per-query latency source available, and disabling it would remove the visibility a real incident needs. |
| `performance-schema-instrument` | `%=OFF` then `statement/%`, `MYSQL_BIN_LOG` cond+mutex, `innodb_log_file` ON | Full wait instrumentation costs measurable latency — the synch instruments record millions of binlog condvar and mutex events per hour, and wait-event instrumentation taxes the same hot code paths it measures. Statement instruments stay on; they are not what costs the latency. |
| `performance-schema-consumer-*` | 5 ON, 3 explicitly OFF | The `=ON` flags only ever *enable* a consumer, so MySQL's defaults stay on unless disabled explicitly. Without the three `=OFF` lines, `events_statements_history` copies every statement into a per-thread ring buffer nothing reads. |
| `innodb_print_all_deadlocks` | ON | `SHOW ENGINE INNODB STATUS` retains only the most recent deadlock; without this, any deadlock not caught live is unrecoverable after the fact. Costs nothing while deadlocks are rare. |
| `slow_query_log` | ON | Statement digests give continuous per-shape aggregates but never an individual execution with its parameters and row counts. |
| `long_query_time` | 0.5 | Half the e2e budget — anything logged is already an incident. Measured cost at this workload: 2 statements across a full run. |
| `log_slow_extra` | ON | Adds rows examined/sent and lock time; entries are much less useful without it. |
| `log_slow_replica_statements` | ON (secondary) | Slow apply on the replica is otherwise invisible. |
| `binlog_group_commit_sync_delay` | 0 | MySQL's default, set explicitly. A nonzero delay holds every commit group in the sync stage to widen batching, taxing every commit's latency; measured at 1000 TPS, 0 beats 10,000 µs by 25–75 ms p99 on every database-touching leg with no throughput cost. |

## 10. Deploy sequence / reproduction

```bash
SLUG=v17.1.0-mtls-mesh-1000tps

unset HTTPS_PROXY https_proxy
make terraform-init
make terraform-plan  SCENARIO=$SLUG
make terraform-apply SCENARIO=$SLUG
make tunnel          SCENARIO=$SLUG
make k8s             SCENARIO=$SLUG
make cilium          SCENARIO=$SLUG   # immediately after k8s, cluster must still be empty
make ebs-csi         SCENARIO=$SLUG   # before deploy — the Kafka and MySQL PVCs need its StorageClasses
make deploy          SCENARIO=$SLUG
make ambient         SCENARIO=$SLUG   # after deploy (which includes mtls)
make load            SCENARIO=$SLUG
```

### Pre-load replication check

A broken replication topology looks identical to a healthy one until a node
fails, so verify it directly before every load.

```bash
# Kafka: expect Isr to list all 3 brokers for every partition
kubectl -n mojaloop exec kafka-controller-0 -c kafka -- bash -c '
export JMX_PORT=
SP=$(ls /opt/bitnami/kafka/config/server.properties /bitnami/kafka/config/server.properties 2>/dev/null | head -1)
{ echo "security.protocol=SSL"
  echo "ssl.endpoint.identification.algorithm="
  echo "ssl.truststore.type=JKS"
  echo "ssl.truststore.location=/opt/bitnami/kafka/config/certs/kafka.truststore.jks"
  echo "ssl.truststore.password=$(grep -m1 "^ssl.truststore.password=" "$SP" | cut -d= -f2-)"
} > /tmp/client.properties
kafka-topics.sh --describe --bootstrap-server kafka:9092 --command-config /tmp/client.properties'

# MySQL secondary: expect Replica_IO_Running and Replica_SQL_Running both Yes
kubectl -n mojaloop exec mysqldb-secondary-0 -- \
  mysql -uroot -p<pw> --vertical -e "SHOW REPLICA STATUS"

# MySQL primary: expect Rpl_semi_sync_source_status ON and a non-zero client count
kubectl -n mojaloop exec mysqldb-primary-0 -- \
  mysql -uroot -p<pw> -e "SHOW GLOBAL STATUS LIKE 'Rpl_semi_sync_source_%';"
```

## 11. k6 results (full-run, unclipped)

Run start 2026-09-24T23:31:45Z, 4,020,000 transactions driven at 1000 TPS over
4,020 s. These are the full-run aggregate including ramp-up and ramp-down, not
the pass/fail number.

```
✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
    ↳  99% — ✓ 4019974 / ✗ 27
✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
    ↳  99% — ✓ 4019968 / ✗ 6
✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
    ↳  99% — ✓ 4019943 / ✗ 23

✓ checks.........................: 99.99%   ✓ 12059885    ✗ 56
✓ completed_transactions.........: 4019943  999.902814/s
  data_received..................: 46 GB    11 MB/s
  data_sent......................: 11 GB    2.8 MB/s
✓ discovery_time.................: avg=17.11ms  min=1ms      med=16ms     max=535ms    p(90)=22ms     p(95)=26ms     p(99)=42ms
✓ quote_time.....................: avg=101.03ms min=38ms     med=96ms     max=1.94s    p(90)=141ms    p(95)=161ms    p(99)=222ms
✓ transfer_time..................: avg=415.23ms min=148ms    med=393ms    max=2.57s    p(90)=579ms    p(95)=655ms    p(99)=824ms
✓ e2e_time.......................: avg=533.55ms min=222ms    med=509ms    max=2.86s    p(90)=711ms    p(95)=791ms    p(99)=981ms
✓ success_rate...................: 99.99%   ✓ 4019943     ✗ 58
  failed_transactions............: 58       0.014427/s
  http_req_duration..............: avg=177.74ms med=95.91ms  max=30s      p(90)=457.35ms p(95)=534.23ms p(99)=709.03ms
  http_req_failed................: 0.00%    ✓ 56          ✗ 12059885
  http_reqs......................: 12059941 2999.736301/s
  iterations.....................: 4020001  999.917241/s
  vus............................: 281      min=0         max=1407
  vus_max........................: 2000     min=2000      max=2000
```

Full-run e2e p99 was 981 ms. Actual throughput 999.90 TPS against a 1000 TPS
target, with no dropped iterations — the arrival-rate executor serviced every
scheduled iteration, so the load actually applied matches the load intended.
Peak VUs of 1,407 against a 2,000 pool leaves the load generator with
headroom, confirming k6 is not itself the constraint.

0.0014% of transactions (58 of 4,020,001) failed a response-code check, spread
across all three legs (27 discovery, 6 quote, 23 transfer wait). At this
failure rate the run is effectively clean; `http_req_failed` rounds to 0.00%.
The `http_req_duration` max of 30 s is the client-side request timeout, so the
handful of failures are requests that never completed rather than requests
that returned an error.

## 12. Steady-state results

**Window:** 2026-09-24T23:36:45Z–2026-09-25T00:36:45Z (3600 s), the standard
start+5 min .. end−2 min trim. **3,599,479 transfers measured in window** at
**999.86 TPS**.

**Validity gate: PASS** — fulfil/prepare = 1.000, notification/prepare = 2.000
(3,599,633 prepare, 3,599,644 fulfil, 7,199,290 notification messages).

Percentiles are reconstructed from k6 native histograms in Prometheus over the
trimmed window.

| Leg | p50 | p95 | **p99** | avg |
|---|---|---|---|---|
| Discovery (party lookup) | 16 ms | 25 ms | **40 ms** | 17 ms |
| Quote | 95 ms | 156 ms | **215 ms** | 99 ms |
| Transfer | 393 ms | 658 ms | **840 ms** | 417 ms |
| **End to end** | **507 ms** | **791 ms** | **996 ms** | **534 ms** |

End to end is the full customer-visible transaction and is not the sum of the
three legs.

### MySQL and replication under load

The database numbers belong with the latency result because the durability
posture is part of what is being claimed — the p99 above is measured with the
binlog fsynced on every commit and every transaction acknowledged by the
replica before the client is released.

| Measure | Value |
|---|---|
| Queries/s (primary) | 21,439 |
| Commits/s (primary) | 2,094 |
| Peak `Threads_connected` | 897 of 6,000 |
| Peak `Threads_running` | 194 |
| Buffer-pool physical reads | 0.4/s against 21.4k queries/s |
| Primary node CPU | 68% avg, 77% peak |
| Queries/s (secondary, replication apply) | 13,459 |
| Commits/s (secondary) | 4,094 |

| Replication | Value |
|---|---|
| Semi-sync fallbacks to async (`Rpl_semi_sync_source_no_tx`) | **0** |
| `Rpl_semi_sync_source_status` / `_replica_status` | ON / ON throughout |
| Semi-sync clients connected | 1 throughout |
| Replica IO/SQL threads running throughout | Yes / Yes, zero errors |
| Replica lag (`Seconds_Behind_Source`) | **0 s for the entire window** |
| Secondary node CPU | 34% avg, 34% peak |

**Zero semi-sync fallbacks.** `Rpl_semi_sync_source_no_tx` did not increment at
any point in the measurement window — every commit in this result was
acknowledged by the replica, not silently downgraded to asynchronous. `Rpl_semi_sync_source_status`
stayed ON with one client connected throughout.

**Replica fully caught up throughout.** `Seconds_Behind_Source` was 0 for the
whole window, both replication threads ran continuously, and `Last_IO_Errno`
and `Last_SQL_Errno` were 0 at every sample. The `sync_binlog` asymmetry
(primary 1, secondary 1000, see §9) is what gives the replica the apply
headroom to stay caught up.

### Transfer leg breakdown

Switch-side stage timings, **means** — means are additive across stages and
percentiles are not, so the two must not be mixed. Sourced from Prometheus
handler histograms (`moja_transfer_*`, `moja_notification_event`) over the
same steady window; the whole-leg figure is k6's own `transfer_time` mean.

| Stage | Mean | Share of leg |
|---|---|---|
| **Whole transfer leg** | **417 ms** | **100%** |
| Ingress produce (ml-api-adapter) | 0.2 ms | 0.1% |
| Prepare handler | 31.0 ms | 7.4% |
| Fulfil handler | 31.3 ms | 7.5% |
| Position-batch handler (×2) | 77.2 ms | 18.5% |
| Notification handler (×2) | 18.8 ms | 4.5% |
| **Between stages (6 Kafka hops)** | **258.8 ms** | **62.1%** |

**The majority of transfer latency is not inside any handler.** The four
handlers together account for 158.2 ms of the 417 ms leg; the remaining
258.8 ms is time between stages across the six Kafka hops.

## 13. Capacity used

Node CPU over the measurement window. No node is saturated; the busiest
generic node peaks at 76%, and the busiest node overall is the MySQL primary
at 77%.

| Node | avg | peak |
|---|---|---|
| sw1-n1 | 50% | 52% |
| sw1-n2 | 43% | 45% |
| sw1-n3 | 52% | 66% |
| sw1-n4 | 61% | 63% |
| sw1-n5 | 50% | 52% |
| sw1-n6 | 62% | 76% |
| sw1-n7 | 49% | 51% |
| sw1-n8 | 58% | 60% |
| sw1-n9 | 44% | 46% |
| sw1-n10 | 63% | 64% |
| sw1-kafka-n1 | 46% | 49% |
| sw1-kafka-n2 | 45% | 46% |
| sw1-kafka-n3 | 38% | 41% |
| sw1-mysql-n1 (primary) | 68% | 77% |
| sw1-mysql-n2 (secondary) | 34% | 34% |
| sw1-monitoring | 7% | 9% |

**MySQL primary** ran at 68% node CPU serving 21,439 queries/s and 2,094
commits/s, with buffer-pool physical reads at 0.4/s against that query volume —
CPU is not the binding constraint on this result.

**The secondary at 34% avg / 34% peak** is sized identically to the primary and
ran at half its utilisation while staying fully caught up — the headroom
semi-sync needs, since an undersized secondary throttles the primary's commit
path, not just its own.

**Generic-node spread is 43–63% avg.** The 20-point spread between the least
and most loaded generic node comes from replica counts that are not multiples
of the node count: the five deployments at 12 replicas each place a second pod
on two of the ten nodes, and those extras are not distributed to different
nodes by the scheduler. Levelling them is worth roughly 10 points on the
busiest node.

## 14. Caveats, concessions, known limitations

- **The replica depends on the `sync_binlog` asymmetry** (§9). A deployment that "hardens" the secondary to `sync_binlog=1` will silently lose its failover currency under sustained load. Durability is unaffected either way — semi-sync acknowledges on relay-log receipt.
- **The slow query log writes to the data volume.** `slow_query_log_file` defaults under `/bitnami/mysql/data`, so its writes consume the same provisioned IOPS as the commit path and nothing rotates it. Harmless at this workload's volume (2 statements exceeded 500 ms across a full run), but a production deployment needs it on a separate volume with size-capped rotation — community MySQL has no slow-log rate limiting to fall back on.
- **Nothing alerts on semi-sync falling back to asynchronous.** The state is scraped (`Rpl_semi_sync_source_no_tx`, `_status`, `_clients`) and was zero throughout this run, but a fallback is silent: the primary disables semi-sync on timeout and keeps committing without it until the replica catches up. Any deployment relying on the durability property must alert on those three series — the expressions are recorded in `overrides/backend.yaml` alongside the semi-sync flags.
- **The 7-core MySQL container limit should not simply be removed.** `overrides/backend.yaml` deliberately leaves 1–2 cores of node headroom for kubelet and the CNI on an 8-core node; lifting the cap trades a latency ceiling for node instability. Adding real headroom means a larger instance.
- **Manual MySQL failover only, no automation.** Semi-sync + persistence gives a durable, up-to-date secondary, but nothing automatically promotes it or repoints the `mysqldb` service alias if the primary dies — that requires a human running a runbook. Deliberately out of scope (judged an operational concern, not a performance one).
- **ISO 27001 Annex A technical-controls scope.** This is a check against which Annex A *technical* controls this deployment's config satisfies, not a full ISMS/governance audit — risk assessment, policy, and training are out of scope for a lab environment. Covered: A.8.24 cryptography in transit (sidecar mTLS + ambient mesh + Kafka/MySQL protocol TLS); A.8.13 backup/persistence (Kafka and MySQL both run on EBS-backed PVs, not ephemeral storage); A.8.10/8.24 data-at-rest encryption (`encrypted: true` on every data volume — zero measured perf cost, since every instance type in this fleet is Nitro-based and encrypts in hardware below the OS rather than as a CPU-competing software layer); A.5.15/8.2 access control (bastion-only SSH, no public ingress); A.8.9 configuration management (values in git). Out of scope: A.8.13 backup/restore drills and A.8.16 audit-log retention — both are live-system operational practices this environment, provisioned and torn down per test cycle, has no ongoing need for.

## 15. Other observations / gotchas found

### Deviations from the stock v17.1.0 chart

Four changes depart from what the chart ships. Each is required for this
scenario's result and none is expressible through stock chart values alone.

**1. DFSP-side mTLS moved from the application to an Istio sidecar and
gateway** (`ansible/roles/istio_dfsp`), with the app's inbuilt TLS disabled
afterwards by `mtls_dfsp`. The mechanism and the reason for it are in §8.

**2. CoreDNS scaled to 3 replicas on the switch cluster**
(`coredns_replicas` in `ansible/roles/cilium/defaults/main.yml`, applied by
`kubectl scale`). MicroK8s ships a single CoreDNS replica, which becomes a
single point of failure and a latency contributor for a cluster resolving
cross-cluster DFSP hostnames on every outbound callback at this request rate.

**3. central-ledger and ml-api-adapter pinned above the chart default on the
transfer path.** `mojaloop/central-ledger:v20.1.0` runs the prepare and
fulfil handlers, and `mojaloop/ml-api-adapter:v16.11.0` runs the
notification handler and the API service. These carry an asynchronous Kafka
offset-commit path (`central-services-shared` 18.39.0-snapshot.1 /
`central-services-stream` 11.19.4-snapshot.1) that the chart's default
versions do not have. Those versions call `commitMessageSync`, which blocks
the Node event loop on every message: with them, event-loop lag p99 on these
three handlers measures 46/43/41 ms versus 16/13/20 ms with the async path,
while unchanged handlers hold steady. Enabled per handler by `"commitStrategy": "async"` alongside
`enable.auto.commit: false` in this scenario's configmap overrides.
The central-ledger image is a TypeScript build running from `dist/`, so it
needs an explicit `command` override — the chart's default `src/handlers/index.js`
does not exist in it.

**4. Kafka consumer poll backoff reduced from 100 ms to 1 ms**
(`recursiveTimeout`, on the prepare, fulfil, notification and position-batch
consumers and on the quoting handler's and quoting service's
`QUOTE.POST`/`QUOTE.PUT` consumers). The consumer loop in
`central-services-stream` is serial and self-clocking: it does not fetch the
next batch until the current one has been fully processed, and on an empty
fetch it sleeps `recursiveTimeout` before looking again. Every Mojaloop service
ships 100 ms. librdkafka's background thread continues filling the local queue
during that sleep, so the message is already present and simply not collected —
measured broker-side fetch activity is roughly one fetch per consumer every
3 ms, confirming delivery is not the constraint.

The setting affects only the empty-fetch branch and cannot change processing
behaviour.

### Chart and platform gotchas

- **`offset_commit_cb` must be absent from `rdkafkaConf`, never set to `false`.** node-rdkafka intercepts only truthy values for it, so `false` falls through to librdkafka's generic property setter and throws `Property "offset_commit_cb" must be set through dedicated .._set_..() function`. The consumers then never start while the HTTP server does, so the pods pass their probes and look healthy while processing nothing.
- **Position-batch runs a blocking offset commit deliberately.** It is the one on-path consumer without `commitStrategy: async`, and its event-loop lag p99 is correspondingly higher (35 ms against 13–20 ms elsewhere), costing roughly 11 ms of leg time. Position updates are incremental and have no duplicate-check guard equivalent to the one protecting prepare and fulfil, so widening the reprocessing window risks double-applying a balance change. The narrower window is worth the latency.

## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/`. Representative panels:

**These captures are from an earlier measurement of this scenario on a previous
build of the environment, not from the run reported in §11–§13.** The dashboards
and panel semantics are unchanged, so they remain an accurate illustration of
what is measured and how, but the absolute values shown in them — e2e p99,
throughput, per-node CPU — belong to that earlier run and will not match the
tables above. Where the two differ, §11–§13 are authoritative.

**K6 Transaction Latency (Client-Observed)** — the SLA-gate metric:
client-observed e2e percentiles and actual throughput against the 1000 TPS
target, over the full run.
![K6 Transaction Latency](<screenshots/K6 Transaction Latency (Client-Observed)/K6 Transaction Latency (Client-Observed) - 1.png>)

**Transfer / Quote / Discovery — Leg Breakdown** — each leg's mean latency
walked hop by hop around the full round trip (payer FSP → switch → payee FSP
→ switch → back to the payer), every on-path handler and network hop shown,
alongside the switch-side internal steps and — for transfer — a Kafka
queueing estimate plus a wide-span closure proof (`tx_transfer_prepare` +
DFSP round trip + `tx_transfer_fulfil` sums to within a few hundred
microseconds of the k6 transfer mean). Transfer is an 11-hop walk spanning
the prepare and fulfil phases: prepare handler, position-batch and
notification handler on each side, the Istio hops to the payee and back, and
the final notification to the payer. Discovery is an 8-hop walk that includes
the ALS → msisdn-oracle call, shown amortized since most lookups resolve from
the ALS participant cache. Quote is a 7-hop walk whose inter-stage remainder
is almost entirely the two `topic-quotes-post`/`-put` Kafka hops, whose
consumer groups export no lag data in this cluster. Discovery closes almost
completely from the directly-measured hops. The transfer Kafka-queueing
panel's `topic-notification-event` series can render as a nonsensical value
("years") right at ramp-down, when that topic's message rate briefly drops
near zero and the lag÷rate estimator's denominator does too — an artifact of
the estimation method, not a real queueing delay.
![Leg Latency by Phase](<screenshots/Transfer — Leg Breakdown/Transfer — Leg Breakdown - 1.png>)
![Discovery Phase Breakdown](<screenshots/Transfer — Leg Breakdown/Transfer — Leg Breakdown - 2.png>)
![Quote Phase Breakdown](<screenshots/Transfer — Leg Breakdown/Transfer — Leg Breakdown - 3.png>)
![Transfer Phase Breakdown](<screenshots/Transfer — Leg Breakdown/Transfer — Leg Breakdown - 4.png>)

**Kafka - Whitepaper Overview** — validity-gate topic partition counts and
message-rate ratios (fulfil:prepare≈1.0, notification:prepare≈2.0).
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**Capacity & Saturation** — node CPU/PSI/memory across the 10-node switch
fleet.
![Capacity & Saturation](<screenshots/Capacity & Saturation/Capacity & Saturation - 1.png>)

**FSP / DFSP Simulator — Capacity** — per-FSP node CPU/memory and
scheme-adapter+backend+cache CPU cores across all 8 FSPs.
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Service Mesh Hop Latency** — Istio hop latency and error rate by
source→destination.
![Service Mesh Hop Latency](<screenshots/Service Mesh Hop Latency/Service Mesh Hop Latency - 1.png>)

**mTLS / Mesh Overhead** — request rate by `connection_security_policy`
(`mutual_tls` versus `none`) and per-pod sidecar CPU cost.
![mTLS Overhead](<screenshots/mTLS : Mesh Overhead/mTLS : Mesh Overhead - 1.png>)

**MySQL Overview** — command throughput, row-access pattern, and InnoDB
redo-log activity on the primary.
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**MySQL Replication** — thread state, replica lag, relay-log backlog, and the
semi-sync durable-ack path, including async fallbacks
(`Rpl_semi_sync_source_no_tx`) and per-commit ack wait.
![MySQL Replication](<screenshots/MySQL Replication/MySQL Replication - 1.png>)

**Mojaloop - Central-Ledger Performance Characterization** — participant
model-cache hit and miss rates.
![Central-Ledger Cache Hits](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

**Central Ledger (Transfer Legs)** — prepare/fulfil handler processing time
by layer (handler ingress / domain logic / model-DB) at p95 and p99.
![Central Ledger Transfer Legs](<screenshots/Central Ledger (Transfer Legs)/Central Ledger (Transfer Legs) - 1.png>)

**Mojaloop - ML-API Adapter** — notification-handler `tx_transfer` wide-span
processing time (contains the full prepare/fulfil round trip end to end,
not an additional leg on top of it).
![ML-API Adapter](<screenshots/Mojaloop - ML-API Adapter/ Mojaloop - ML-API Adapter - 2.png>)

**Mojaloop - ALS** and **Mojaloop - Quoting Service** — party-lookup and
quote ingress processing time. The ingress p95/p99 lines on these two
dashboards read as flat, exact values (9.50ms/9.90ms) — a fixed
classic-histogram bucket boundary these metrics hit, not a real
measurement; the Leg Breakdown dashboard above has the real per-hop numbers
for both legs.
![Mojaloop ALS](<screenshots/Mojaloop - ALS/Mojaloop - ALS - 1.png>)

Additional captures for every dashboard above are in their respective
`screenshots/` subfolders.
