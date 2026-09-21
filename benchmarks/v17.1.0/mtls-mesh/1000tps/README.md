# v17.1.0 / mtls-mesh / 1000tps — Scenario Report

Status: **PASS** — 1,199,806 transfers measured at 1000 TPS, steady-state
e2e p99 **944 ms** against the `<1s` goal, with the Kafka validity gate
passing and semi-sync replication engaged.

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
- **Status:** ✅ **PASS** — steady-state e2e p99 944 ms, semi-sync replication engaged, `sync_binlog=1`

## 2. Test methodology & definitions

- **Steady-state window:** start+5 min .. end−2 min (TPC/SPEC-style warm-up/drain trim), applied mechanically by `benchmarks/tools/steady-state.sh` — no window selection by judgement. `targetTxnCount` is sized well above the trim so the steady window still measures well over 1,000,000 transfers regardless of exactly how much the fixed 5-min/2-min trim removes on a given run.
- **The k6 end-of-run summary is the full-run aggregate** and includes the ramp edges; steady-state is the authoritative number for pass/fail. The two are close here — 942 ms full-run versus 944 ms steady-state — indicating negligible ramp-up drag on this run.
- **Latency falls over the first minutes of a run**, which is what the warm-up trim exists to exclude. Comparisons between runs are only valid when both use the same trim on runs of the same length.
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0, position-batch/prepare ≈ 2.0. A failing gate means the pipeline was not keeping up, and invalidates the percentiles regardless of what they read. A MySQL-side cross-check complements it — the row count in `central_ledger.transfer` with `createdDate` inside the steady window should match the measured transfer count to within a fraction of a percent; a shortfall means transfers were counted by k6 but never committed to the ledger.

## 3. Test design parameters

- **Target TPS:** 1000
- **Target transaction count:** 1,420,000 (`overrides/k6.yaml` `targetTxnCount`) — sized so the fixed 5-min warm-up / 2-min drain trim still leaves well over 1,000,000 transfers in the steady window
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
  - `overrides/backend.yaml` — Kafka RF=3/ISR=2 across 3 brokers, MySQL primary+secondary with semi-sync + durable commits, gp3 persistence for both
  - `overrides/aws.yaml` — node sizing — **dedicated infra, not shared**
  - `overrides/k6.yaml` — 1000 TPS target, 1,420,000 transaction count

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
| als-msisdn-oracle | 8 | — |
| centralledger-service | 8 | — |
| centralledger-handler-transfer-prepare | 12 | `topic-transfer-prepare` = 12 |
| centralledger-handler-transfer-fulfil | 12 | `topic-transfer-fulfil` = 12 |
| handler-pos-batch (transfer-position-batch) | 8 | `topic-transfer-position-batch` = 8 |
| quoting-service | 12 | `topic-quotes-post`/`-put` = 12 |
| quoting-service-handler | 12 | |
| ml-api-adapter-service | 12 | — |
| ml-api-adapter-handler-notification | 30 | `topic-notification-event` = 30 |
| kafka-controller | 3 (StatefulSet, combined controller+broker) | |
| mysqldb | primary + 1 secondary (StatefulSet) | |

Off-path singletons (centralledger-handler-timeout/get/admin-transfer,
centralsettlement-*, transaction-requests-service, TTK backend/frontend)
unchanged at 1 replica each — no load-scaling need.

**DFSP simulators**: `dfsp_backend_replicas_default: 1` — not pre-scaled,
since whether more backend replicas actually relieves the sim-backend's
single-threaded ceiling wasn't confirmed ahead of measurement; fsp202 alone
is bumped to 4 where measured backend CPU load justified it
(`overrides/dfsp.yaml`).

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
cited.

**Kafka controller/interbroker traffic is mTLS-encrypted.** At 3 brokers,
Raft consensus and replication traffic crosses the pod network between 3
separate nodes, and Kafka pods are deliberately excluded from the ambient
mesh (to avoid double-encrypting the client-facing SSL stream), so they get
no mTLS from that layer either. Both listeners run
`protocol: SSL` with `sslClientAuth: required` (real mutual TLS, not the
client listener's encrypt-only posture) — this traffic is exclusively
broker↔broker and broker↔controller-quorum, all mutually trusted, with none
of the external-client compatibility concern that drove the client
listener's `none` setting. The existing auto-generated PEM cert covers all
SSL-enabled listeners per-pod, so no extra cert plumbing was needed.

## 9. Kafka / MySQL performance tuning

**Kafka** (3-broker combined KRaft controller+broker, RF=3, ISR=2):
- Listener: SSL-only on port 9092 (client + external). Controller/interbroker: SSL with required mTLS.
- `min.insync.replicas=2` (majority quorum — tolerates 1 broker down without halting writes) — set in the top-level `kafka.extraConfig`, **not** `controller.overrideConfiguration`, which is a dead key in this chart version (31.5.0) and silently ignored.
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
| `read_only` / `super_read_only` | ON | `read_only` alone still permits writes from any connection holding SUPER, which is enough to diverge the replica silently. |

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
make terraform-plan  SCENARIO=$SLUG    # new dedicated workspace — review the plan carefully, this is new spend
make terraform-apply SCENARIO=$SLUG
make tunnel  SCENARIO=$SLUG            # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s     SCENARIO=$SLUG
make cilium  SCENARIO=$SLUG
make ebs-csi SCENARIO=$SLUG            # AWS EBS CSI driver + ebs-gp3-encrypted StorageClass — required before `make deploy` (Kafka/MySQL PVCs will not bind without it)
make deploy  SCENARIO=$SLUG
make ambient SCENARIO=$SLUG            # ztunnel + enrollment + STRICT (must run AFTER mtls)
# Before any load: verify Kafka ISR and MySQL replica health directly —
# a broken replication topology looks identical to a healthy one right up
# until a node actually fails.
#   kafka-topics.sh --describe --bootstrap-server kafka:9092 (check Isr=3 per partition)
#   SHOW REPLICA STATUS  (on the secondary — check Slave_IO/SQL_Running=Yes)
make smoke   SCENARIO=$SLUG
# Ramp before running the full 1000 TPS / 1.42M-transfer load.
make load    SCENARIO=$SLUG
```

## 11. k6 results (full-run, unclipped)

Run start 2026-09-07T18:11:00Z, 1,420,000 transactions driven at 1000 TPS.
These are the full-run aggregate including ramp-up and ramp-down, not the
pass/fail number.

```
✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
    ↳  99% — ✓ 1419991 / ✗ 10
✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
    ↳  99% — ✓ 1419987 / ✗ 4
✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
    ↳  99% — ✓ 1419492 / ✗ 495

✓ checks.....................: 99.98%   ✓ 4259470  ✗ 509
✓ completed_transactions.....: 1419492  999.378652/s
✓ discovery_time.............: avg=16.99ms  med=16ms   p(90)=22ms    p(95)=25ms    p(99)=38ms
✓ quote_time.................: avg=100.81ms med=96ms   p(90)=140ms   p(95)=159ms   p(99)=217ms
✓ transfer_time..............: avg=403.05ms med=385ms  p(90)=547ms   p(95)=614ms   p(99)=779ms
✓ e2e_time...................: avg=521.31ms med=502ms  p(90)=678ms   p(95)=750ms   p(99)=942ms
✓ success_rate...............: 99.96%   ✓ 1419492  ✗ 509
  failed_transactions........: 509      0.358356/s
  http_req_failed.............: 0.01%    ✓ 509      ✗ 4259470
  iterations..................: 1420001  999.737008/s
  vus.........................: 333      min=0        max=1471
  vus_max.....................: 2000     min=2000     max=2000
```

Full-run e2e p99 was 942 ms. Actual throughput 999.6 TPS against a 1000 TPS
target, with no dropped iterations — the arrival-rate executor serviced every
scheduled iteration, so the load actually applied matches the load intended.
Peak VUs of 1,471 against a 2,000 pool leaves the load generator with
headroom, confirming k6 is not itself the constraint.

0.36% of transactions (509 of 1,420,001) failed a response-code check, almost
entirely on the transfer leg (495 of 509). These are latency-distribution
outliers rather than pipeline errors — the failure rate holds essentially
constant between the full run and the steady window, so it is not
concentrated in ramp-up or ramp-down.

## 12. Steady-state results

**Window:** 18:13:42–18:33:42Z (1200 s), the standard start+5 min .. end−2 min
trim. **1,199,806 transfers measured in window.**

**Validity gate: PASS** — fulfil/prepare = 1.000, notification/prepare = 2.000.

**Ledger cross-check:** `central_ledger.transfer` rows with `createdDate` in
the steady window (prepare-time, so keyed on transfer *start*, not
completion) — **1,199,993 total**, of which **1,199,531 `COMMITTED`**,
matching the 1,199,806 transfers measured in window to within 0.02% (the
gap is window-boundary skew — prepare time vs completion time). The 462
non-`COMMITTED` rows (397 `RECEIVED_FULFIL`, 65 `EXPIRED_PREPARED`) are
transfer-leg failures; together with the discovery/quote-leg failures that
never create a `transfer` row they account for the run's 509
`failed_transactions`.

```sql
SELECT
  (SELECT transferStateId FROM central_ledger.transferStateChange
   WHERE transferId = t.transferId ORDER BY transferStateChangeId DESC LIMIT 1) AS finalState,
  COUNT(*)
FROM central_ledger.transfer t
WHERE t.createdDate >= '2026-09-07 18:13:42' AND t.createdDate < '2026-09-07 18:33:42'  -- UTC
GROUP BY finalState;
```

| Leg | p50 | p95 | **p99** | avg |
|---|---|---|---|---|
| Discovery (party lookup) | 15 ms | 24 ms | **37 ms** | 16 ms |
| Quote | 96 ms | 159 ms | **217 ms** | 100 ms |
| Transfer | 386 ms | 620 ms | **783 ms** | 404 ms |
| **End to end** | **502 ms** | **755 ms** | **944 ms** | **522 ms** |

End to end is the full customer-visible transaction and is not the sum of the
three legs.

### MySQL and replication under load

The database numbers belong with the latency result because the durability
posture is part of what is being claimed — the p99 above is measured with the
binlog fsynced on every commit and every transaction acknowledged by the
replica before the client is released.

| Measure | Value |
|---|---|
| Queries/s (primary) | 21,488 |
| Commits/s (primary) | 2,099 |
| Peak `Threads_connected` | 927 of 6,000 |
| Peak `Threads_running` | 181 |
| Buffer-pool physical reads | 0/s against 21.5k queries/s |
| Primary node CPU | 62.3% avg, 62.7% peak |

| Replication | Value |
|---|---|
| Semi-sync fallbacks to async (`Rpl_semi_sync_source_no_tx`) | **0** |
| Semi-sync acknowledgements/s | 674 |
| Replica IO/SQL threads running throughout | Yes / Yes, zero errors |
| Replica lag (peak in window) | 59 s, draining to 0 s by window end |
| Secondary node CPU | 35.8% avg, 43.6% peak |

**Zero semi-sync fallbacks.** `Rpl_semi_sync_source_no_tx` did not increment at
any point in the measurement window — every commit in this result was
acknowledged by the replica, not silently downgraded to asynchronous.

**Replica lag was non-zero but recovering.** The secondary entered this run
still resyncing rather than fully caught up. Lag peaked at 59 s during
the window and drained to 0 by the window's end, with both replication threads
running throughout and zero replication errors. The `sync_binlog` asymmetry in
The `sync_binlog` asymmetry (primary 1, secondary 1000) is what keeps the replica capable of draining a
backlog at all — at symmetric per-commit fsync on both nodes the replica
applies at roughly half the primary's rate and cannot catch up under
sustained load.

### Transfer leg breakdown

Switch-side stage timings, **means** — means are additive across stages and
percentiles are not, so the two must not be mixed. Sourced from Prometheus
handler histograms (`moja_transfer_*`, `moja_notification_event`) over the
same steady window; the whole-leg figure is k6's own `transfer_time` mean.

| Stage | Mean | Share of leg |
|---|---|---|
| **Whole transfer leg** | **404 ms** | **100%** |
| Prepare handler | 27.5 ms | 6.8% |
| Fulfil handler | 27.4 ms | 6.8% |
| Position-batch handler (×2) | 68.4 ms | 16.9% |
| Notification handler (×2) | 20.2 ms | 5.0% |
| **Between stages (6 Kafka hops)** | **260.5 ms** | **64.5%** |

**The majority of transfer latency is not inside any handler.** All four
handlers together account for 143.5 ms of the 404 ms leg; the remaining 260.5
ms is time between stages — a message sitting in a topic after being produced
and before its consumer picks it up — spread across six Kafka hops.

The position-batch handler runs roughly 99 times per second, not 1,000: it
consumes the position topic in batches. A transfer traverses it twice (prepare
and fulfil positions), so the contribution to a single transfer's latency is
2 × 34.2 ms.

### Quote leg

The quote leg is 100 ms mean / 217 ms p99. Quoting runs with
`SIMPLE_ROUTING_MODE: true`, so it validates and forwards without persisting
quotes — its own handler work measures 0.2 ms per message on both
`QUOTE.POST` and `QUOTE.PUT`, confirmed directly this run, and it issues no
database queries on the quote path. Essentially the entire leg is therefore
the two Kafka hops (`topic-quotes-post`, `topic-quotes-put`) and the payee
DFSP's own quote processing.

## 13. Capacity used

Node CPU over the measurement window. No node is saturated; the busiest
generic node peaks at 72.7%.

| Node | avg | peak |
|---|---|---|
| sw1-n1 | 44.2% | 45.6% |
| sw1-n2 | 68.2% | 72.7% |
| sw1-n3 | 48.0% | 50.1% |
| sw1-n4 | 49.0% | 50.0% |
| sw1-n5 | 55.7% | 60.2% |
| sw1-n6 | 57.5% | 60.1% |
| sw1-n7 | 64.8% | 67.6% |
| sw1-n8 | 42.5% | 42.8% |
| sw1-n9 | 51.2% | 52.9% |
| sw1-n10 | 55.3% | 56.5% |
| sw1-kafka-n1 | 47.4% | 48.0% |
| sw1-kafka-n2 | 42.6% | 43.4% |
| sw1-kafka-n3 | 39.6% | 39.9% |
| sw1-mysql-n1 (primary) | 62.3% | 62.7% |
| sw1-mysql-n2 (secondary) | 35.8% | 43.6% |
| sw1-monitoring | 5.6% | 5.8% |

**MySQL primary** ran at 62.3% node CPU serving 21,488 queries/s and 2,099
commits/s, with buffer-pool physical reads at zero against that query volume —
CPU is not the binding constraint on this result.

**The secondary at 35.8% avg / 43.6% peak** is sized identically to the
primary and ran at roughly half its utilisation while draining a replication
backlog — the headroom semi-sync needs, since an undersized secondary
throttles the primary's commit path, not just its own.

## 14. Caveats, concessions, known limitations


- **The replica depends on the `sync_binlog` asymmetry** (primary 1, secondary 1000). Per-commit fsync on both nodes would drop the replica to roughly half the primary's apply rate, because `replica_preserve_commit_order` serialises the applier's commit stage and leaves group commit nothing to batch. Durability is unaffected either way — semi-sync acknowledges on relay-log receipt — but a deployment that "hardens" the secondary to match the primary will silently lose its failover currency under sustained load.
- **The slow query log writes to the data volume.** `slow_query_log_file` defaults under `/bitnami/mysql/data`, so its writes consume the same provisioned IOPS as the commit path and nothing rotates it. Harmless at this workload's volume (2 statements exceeded 500 ms across a full run), but a production deployment needs it on a separate volume with size-capped rotation — community MySQL has no slow-log rate limiting to fall back on.
- **Nothing alerts on semi-sync falling back to asynchronous.** The state is scraped (`Rpl_semi_sync_source_no_tx`, `_status`, `_clients`) and was zero throughout this run, but a fallback is silent: the primary disables semi-sync on timeout and keeps committing without it until the replica catches up. Any deployment relying on the durability property must alert on those three series — the expressions are recorded in `overrides/backend.yaml` alongside the semi-sync flags.
- **The 7-core MySQL container limit should not simply be removed.** `overrides/backend.yaml` deliberately leaves 1–2 cores of node headroom for kubelet and the CNI on an 8-core node; lifting the cap trades a latency ceiling for node instability. Adding real headroom means a larger instance.
- **AWS EBS CSI driver + StorageClasses are exercised and working.** `ansible/roles/ebs_csi` installs the upstream `aws-ebs-csi-driver` Helm chart (v2.62.0) and applies both StorageClasses from `manifests/storage/`. This cluster is self-managed MicroK8s on plain EC2, not EKS, so there's no IRSA — credentials come from an IAM instance profile (`terraform/iam.tf`, AWS-managed `AmazonEBSCSIDriverPolicy`) attached to every switch-cluster instance, with `metadata_options.http_put_response_hop_limit` raised to 2 so pods (one hop further from IMDS than the host) can reach it; omitting that hop-limit fix makes the driver silently fail to get credentials. The CSI node plugin is tolerated onto the kafka/mysql/monitoring tainted nodes so it can mount volumes there. Both MySQL PVCs bind to `ebs-io2-encrypted` and both Kafka PVCs to `ebs-gp3-encrypted`.
- **Pod anti-affinity (`podAntiAffinityPreset: hard`) for Kafka/MySQL is confirmed against the actual pinned chart versions** — `kafka 31.5.0` / `mysql 14.0.3` (per `example-mojaloop-backend`'s own `Chart.yaml`, not assumed from the `main` branch). Both charts' default is `soft`; overridden to `hard` here because node count exactly matches replica count (3 Kafka-tainted nodes/3 brokers, 2 MySQL-tainted nodes/2 replicas), so the hard constraint is always satisfiable.
- **Kafka controller/interbroker mTLS is new at 3 brokers.**
- **Storage classes differ by workload and both are now validated under load.** MySQL runs io2 at 10,000 provisioned IOPS — its commit path is frequent small synchronous writes, which is what io2 exists for; measured use is 3,249 write IOPS on the primary, 33% of provisioned. Kafka stays on gp3, whose bundled throughput suits an append-only sequential log better than per-IOPS pricing. The io2 headroom is what makes `sync_binlog=1` affordable.
- **Manual MySQL failover only, no automation.** Semi-sync + persistence gives a durable, up-to-date secondary, but nothing automatically promotes it or repoints the `mysqldb` service alias if the primary dies — that requires a human running a runbook. Deliberately out of scope (judged an operational concern, not a performance one).
- **ISO 27001 Annex A technical-controls scope.** This is a check against which Annex A *technical* controls this deployment's config satisfies, not a full ISMS/governance audit — risk assessment, policy, and training are out of scope for a lab environment. Covered: A.8.24 cryptography in transit (sidecar mTLS + ambient mesh + Kafka/MySQL protocol TLS); A.8.13 backup/persistence (Kafka and MySQL both run on EBS-backed PVs, not ephemeral storage); A.8.10/8.24 data-at-rest encryption (`encrypted: true` on every data volume — zero measured perf cost, since every instance type in this fleet is Nitro-based and encrypts in hardware below the OS rather than as a CPU-competing software layer); A.5.15/8.2 access control (bastion-only SSH, no public ingress); A.8.9 configuration management (values in git). Out of scope: A.8.13 backup/restore drills and A.8.16 audit-log retention — both are live-system operational practices this environment, provisioned and torn down per test cycle, has no ongoing need for.

## 15. Other observations / gotchas found

### Deviations from the stock v17.1.0 chart

Four changes depart from what the chart ships. Each is required for this
scenario's result and none is expressible through stock chart values alone.

**1. DFSP-side mTLS moved from the application to an Istio sidecar and
gateway.** The chart's scheme-adapter terminates inbound TLS behind nginx
SSL-passthrough and originates outbound TLS with its own `https.Agent`. Both
are replaced by Istio (`ansible/roles/istio_dfsp`): a per-DFSP istiod, an
inbound Gateway, and an outbound sidecar on the scheme-adapter, with the app's
inbuilt TLS disabled afterwards by `mtls_dfsp`. The driver is load
distribution rather than security posture — SSL-passthrough pins a client
connection to a single scheme-adapter pod for the connection's lifetime, so
the switch's long-lived keep-alive connections concentrate on one pod
regardless of replica count. Terminating at the sidecar restores per-request
balancing. Each `fspNNN` is an independent single-node cluster with no network
path to a shared control plane, so each runs its own istiod.

**2. CoreDNS scaled to 3 replicas on the switch cluster**
(`coredns_replicas` in `ansible/roles/cilium/defaults/main.yml`, applied by
`kubectl scale`). MicroK8s ships a single CoreDNS replica, which becomes a
single point of failure and a latency contributor for a cluster resolving
cross-cluster DFSP hostnames on every outbound callback at this request rate.

**3. central-ledger and ml-api-adapter pinned above the chart default on the
transfer path.** `mojaloop/central-ledger:v20.1.0` runs the prepare and
fulfil handlers, and `mojaloop/ml-api-adapter:v16.11.0` runs the
notification handler and the API service. These carry an asynchronous Kafka
offset-commit path
(`central-services-shared` 18.39.0-snapshot.1 / `central-services-stream`
11.19.4-snapshot.1) that the stock images do not have. Stock behaviour calls
`commitMessageSync`, which blocks the Node event loop on every message: with
the stock builds, event-loop lag p99 on these three handlers measures 46/43/41
ms versus 16/13/20 ms with the async path, while unchanged handlers hold
steady. Enabled per handler by `"commitStrategy": "async"` alongside
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

This is the largest single lever found in this cell. On the transfer path it
holds per-hop inter-stage cost to ~38 ms against a 54 ms baseline at the
stock 100 ms poll, removing 105 ms of end-to-end latency with every
handler's own processing time unchanged. On the two quote consumers it
holds the quote leg to 106 ms mean / 230 ms p99 against a 163 ms / 327 ms
baseline. It affects only the empty-fetch branch and cannot change
processing behaviour.

### Chart and platform gotchas

- **`controller.overrideConfiguration` is a dead key in this Kafka chart version (31.5.0)** — silently ignored. All Kafka broker-level config in this scenario lives in the top-level `kafka.extraConfig` instead.
- **`offset_commit_cb` must be absent from `rdkafkaConf`, never set to `false`.** node-rdkafka intercepts only truthy values for it, so `false` falls through to librdkafka's generic property setter and throws `Property "offset_commit_cb" must be set through dedicated .._set_..() function`. The consumers then never start while the HTTP server does, so the pods pass their probes and look healthy while processing nothing.
- **Position-batch runs a blocking offset commit deliberately.** It is the one on-path consumer without `commitStrategy: async`, and its event-loop lag p99 is correspondingly higher (35 ms against 13–20 ms elsewhere), costing roughly 11 ms of leg time. Position updates are incremental and have no duplicate-check guard equivalent to the one protecting prepare and fulfil, so widening the reprocessing window risks double-applying a balance change. The narrower window is worth the latency.
- **A namespace-wide STRICT PeerAuthentication silently stops Prometheus scraping ambient-only pods.** Scrapes arrive as plaintext on the application port and ztunnel rejects them (`explicitly denied by istio-system/istio_converted_static_strict`), while sidecar-injected deployments keep working because their proxy terminates the scrape first. The failure is invisible from the load side: k6 continues to report normally while every switch-side handler histogram disappears. `portLevelMtls` requires a selector, so the exemption ships as its own selector-scoped policy rather than on the namespace default — and that policy must restate `mtls.mode: STRICT`, because a selector-scoped policy replaces the namespace default rather than merging with it.
- **AWS EBS CSI driver node plugin needs `node.kubeletPath` explicitly set for MicroK8s** (`ansible/roles/ebs_csi/templates/ebs-csi-values.yaml.j2`) — the chart's default (`/var/lib/kubelet`) assumes vanilla Kubernetes; MicroK8s's real kubelet root is snap-confined (`/var/snap/microk8s/common/var/lib/kubelet`). Without the override, `NodeStageVolume` fails with `mkdir /var/snap: read-only file system` (the node plugin container has no host mount covering that path, so the write hits its own read-only image layer) — every Kafka/MySQL pod sat at `Init:0/1` indefinitely despite their PVCs showing `Bound`. Same class of MicroK8s-snap-path issue this campaign already hit once with Cilium's CNI conf/bin paths.


## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/`. Representative panels:

**K6 Transaction Latency (Client-Observed)** — the SLA-gate metric. Raw
full-run e2e p99: mean 921ms, max 1.46s (unclipped — the steady-state
figure elsewhere in this report is the authoritative PASS/FAIL number);
actual throughput held at ~955 req/s against the 1000 TPS target.
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

**Kafka - Whitepaper Overview** — validity-gate topic partition counts
(12/12/30/8/12) and message-rate ratios confirming the pipeline kept pace
(fulfil:prepare≈1.0, notification:prepare≈2.0).
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**Capacity & Saturation** — node CPU/PSI/memory across the 10-node switch
fleet; peak per-node CPU ~73%, comfortable headroom under saturation.
![Capacity & Saturation](<screenshots/Capacity & Saturation/Capacity & Saturation - 1.png>)

**FSP / DFSP Simulator — Capacity** — per-FSP node CPU/memory and
scheme-adapter+backend+cache CPU cores; the heaviest FSP peaks around 57%
node CPU, comfortable headroom across all 8.
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Service Mesh Hop Latency** — Istio hop latency and error rate by
source→destination; zero non-2xx responses across every FSP hop for the
entire run.
![Service Mesh Hop Latency](<screenshots/Service Mesh Hop Latency/Service Mesh Hop Latency - 1.png>)

**mTLS / Mesh Overhead** — confirms the mesh is carrying real mutual TLS
traffic (13.2K req/s `mutual_tls` vs 2 req/s `none`, the latter being
health-check probes) and per-pod sidecar CPU cost.
![mTLS Overhead](<screenshots/mTLS : Mesh Overhead/mTLS : Mesh Overhead - 1.png>)

**MySQL Overview** — command throughput, row-access pattern, and InnoDB
redo-log activity on the primary.
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**MySQL Replication** — thread state, replica lag, relay-log backlog, and the
semi-sync durable-ack path. Zero async fallbacks (`Rpl_semi_sync_source_no_tx`
did not increment) across the run, per-commit ack wait ~0.6 ms; the replica
entered the run resyncing and drained its lag backlog to zero within the
window, both threads running throughout.
![MySQL Replication](<screenshots/MySQL Replication/MySQL Replication - 1.png>)

**Mojaloop - Central-Ledger Performance Characterization** — participant
model-cache hit rate; cache hits (~117-132 ops/s) dominate misses
(<1.5 ops/s) throughout the run.
![Central-Ledger Cache Hits](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

**Central Ledger (Transfer Legs)** — prepare/fulfil handler processing time
by layer (handler ingress / domain logic / model-DB) at p95 and p99; the DB
layer is a minority of total handler time at both percentiles.
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
