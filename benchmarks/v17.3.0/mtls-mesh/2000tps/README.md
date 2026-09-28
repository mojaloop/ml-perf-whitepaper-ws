# v17.3.0 / mtls-mesh / 2000tps — Scenario Report

Status: **PASS** — 7,193,015 transfers measured at 2000 TPS, steady-state
e2e p99 **1727 ms** against the `<2s` goal for this load level, with the Kafka
validity gate passing and semi-sync replication engaged.

This scenario runs the mtls-mesh security posture (Istio ambient service mesh
+ Kafka/MySQL protocol TLS) at 2000 TPS with real Kafka/MySQL replication.
There is no durability concession behind the result. MySQL runs full
per-commit durability (`sync_binlog=1`, `innodb_flush_log_at_trx_commit=1`),
with every committed transaction acknowledged by the replica before the client
sees it and zero fallbacks to asynchronous across the run. Kafka runs RF=3
with `min.insync.replicas=2` (majority quorum — tolerates one broker down
without halting writes) and `request.required.acks=all` on every producer on
the transfer, quote and notification paths, so a message is acknowledged only
once every broker in the current in-sync-replica set has it, not just the
leader.

The throughput target is met in full — 1998.0 actual TPS against 2000 target,
0.014% dropped iterations, and a validity gate that passes on every topic
ratio. Latency is dominated by the transfer leg's six sequential Kafka hops,
which cost 518 ms of inter-stage transit on their own, before any handler does
work.

## 1. Scenario

- **Version:** v17.3.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 2000 TPS, 4 FSP pairs (4 payer FSPs → 4 payee FSPs, 25% each)
- **Run length:** 67 minutes, yielding a 60-minute steady-state measurement window
- **Status:** ✅ **PASS** — steady-state e2e p99 1727 ms against the `<2s` goal

## 2. Test methodology & definitions

- **Steady-state window:** start+5 min .. end−2 min (TPC/SPEC-style warm-up/drain trim), applied mechanically by `benchmarks/tools/steady-state.sh` — no window selection by judgement.
- **The k6 end-of-run summary is the full-run aggregate** and includes the ramp edges; steady-state is the authoritative number for pass/fail. The two are within 3 ms on this run (1724 ms full-run versus 1727 ms steady-state), because a 67-minute run dilutes the ramp edges to a negligible fraction of the sample.
- **Validity gate:** Kafka topic rate ratios in the steady window — fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0, position-batch/prepare ≈ 2.0. A failing gate means the pipeline was not keeping up, and invalidates the percentiles regardless of what they read.
- **Dataset state is recorded per run.** Table sizes grow by roughly 2.6 GiB per 1.42M transfers, so a run against a populated schema is not directly comparable to one against empty tables. This run started from empty tables.
- **Leg timings are means, not percentiles.** Percentiles are not additive, so the hop-by-hop budget explains the mean leg and cannot be summed to explain the p99.

## 3. Test design parameters

- **Target TPS:** 2000
- **Target transaction count:** 8,040,000 (`overrides/k6.yaml` `targetTxnCount`) — run duration is derived as `targetTxnCount / targetTps` with no ramp stage, so this yields 4020 s of wall clock and exactly 3600 s of steady window after the fixed 300 s / 120 s trim
- **Transfer amount / currency:** 1 XXX
- **Test load distribution** (`overrides/k6.yaml`):

| Source (Payer) | → fsp202 | → fsp204 | → fsp206 | → fsp208 | Total generated |
|---|---|---|---|---|---|
| fsp201 | 25% | – | – | – | **25%** |
| fsp203 | – | 25% | – | – | **25%** |
| fsp205 | – | – | 25% | – | **25%** |
| fsp207 | – | – | – | 25% | **25%** |
| **Total received** | **25%** | **25%** | **25%** | **25%** | **100%** |

Load is spread evenly across all four pairs. Position messages are keyed by
`participantCurrencyId`, so a participant's share of the load is directly its
partition's share of `topic-transfer-position-batch` — an even split keeps the
busiest account off a single saturated partition.

## 4. Hardware / infrastructure

| Role | Count | Instance type | vCPU / RAM |
|---|---|---|---|
| Switch application nodes | 20 | `m7i.2xlarge` | 8 / 32 GiB |
| Kafka nodes | 3 | `m7i.2xlarge` | 8 / 32 GiB |
| MySQL nodes | 2 | `m7i.4xlarge` | 16 / 64 GiB |
| Monitoring node | 1 | `m7i.2xlarge` | 8 / 32 GiB |
| DFSP nodes (`fsp201`–`fsp208`) | 8 | `c7i.4xlarge` | 16 / 32 GiB |
| k6 load generator | 1 | `m7i.2xlarge` | 8 / 32 GiB |
| Bastion | 1 | `t3.small` | 2 / 2 GiB |

All eight DFSP nodes are sized identically because the load distribution gives
each an equal share; no FSP carries more traffic than any other. All nodes sit
in a cluster placement group for low inter-node latency.

### Cluster architecture (MicroK8s)

**Switch cluster.** 26 nodes forming one MicroK8s cluster — 20 application
nodes, 3 Kafka, 2 MySQL, 1 monitoring. Cilium provides the CNI in eBPF native
routing mode. The switch application replica counts are chosen as multiples of
the 20-node application pool so pods distribute evenly rather than leaving
nodes idle.

**DFSP clusters.** Eight independent single-node MicroK8s clusters, one per
FSP. Each runs its own istiod, its own ingress gateway and its own
scheme-adapter, backend and cache deployments. They share no control plane
with the switch or with each other.

**k6 cluster.** A single node running the k6 Operator, with `parallelism: 1`
so the configured `targetTps` is the effective total rate.

Network isolation and cross-cluster DNS are handled together: every cluster
sits in the same private VPC with no public ingress, DFSP→switch traffic
resolves the switch NLB by its private IP, and switch→DFSP traffic resolves
`sim-fspNNN.local` through `hostAliases` pointing at the real DFSP node IP.
Nothing traverses the public internet, and no cluster's API server is
reachable from outside the VPC except through the bastion.

## 5. System-level overrides

- Kernel pinned to `6.17.0-1013-aws` on the switch nodes (`aws.yaml` `k8s.app_node_kernel`) — the GA 6.8 kernel runs measurably higher softirq under sustained packet load. DFSP and k6 nodes stay on the image default.
- Swap disabled, `br_netfilter` and `overlay` modules loaded, `net.ipv4.ip_forward=1` and the bridge netfilter sysctls set on every node.

## 6. Helm chart versions + values overrides

| Chart | Version |
|---|---|
| `mojaloop` | 17.3.0 (installed from a local checkout — this version is not yet published to the mojaloop Helm repo) |
| `mojaloop-backend` | 17.1.0 |
| `mojaloop-simulator` | 15.10.0 |

`mysql.architecture: replication` means the backend chart creates only
`mysqldb-primary` and `mysqldb-secondary` Services, not a plain `mysqldb` one,
while every Mojaloop service's `db_host` still expects `mysqldb` — so a
`mysqldb` Service alias is created alongside, pointing at the primary.

### Transfer-path images

| Deployment | Image |
|---|---|
| `ml-api-adapter-service` | `mojaloop/ml-api-adapter:v16.11.1` |
| `ml-api-adapter-handler-notification` | `mojaloop/ml-api-adapter:v16.11.1` |
| `centralledger-service` | `mojaloop/central-ledger:v20.2.0` |
| `centralledger-handler-transfer-prepare` | `mojaloop/central-ledger:v20.2.0` |
| `centralledger-handler-transfer-position-batch` | `mojaloop/central-ledger:v20.2.0` |
| `centralledger-handler-transfer-fulfil` | `mojaloop/central-ledger:v20.2.0` |

## 7. Pod distribution & replica counts

| Deployment | Replicas | Sizing basis |
|---|---|---|
| `account-lookup-service` | 60 | 3 per application node |
| `als-msisdn-oracle` | 20 | 1 per application node |
| `quoting-service` | 20 | 1 per application node |
| `quoting-service-handler` | 20 | matches `topic-quotes-post` partition count |
| `ml-api-adapter-service` | 20 | 1 per application node |
| `ml-api-adapter-handler-notification` | 60 | matches `topic-notification-event` partition count |
| `centralledger-service` | 2 | off transfer hot path — only backs occasional participant-endpoint lookups |
| `centralledger-handler-transfer-prepare` | 20 | matches `topic-transfer-prepare` partition count |
| `centralledger-handler-transfer-position-batch` | 8 | matches `topic-transfer-position-batch` partition count |
| `centralledger-handler-transfer-fulfil` | 20 | matches `topic-transfer-fulfil` partition count |
| `centralledger-handler-transfer-position` | disabled | superseded by the batch handler |

Every consumer deployment's replica count equals its topic's partition count,
because a Kafka consumer group cannot put more consumers on a topic than it
has partitions — extra replicas sit permanently idle while still holding a
database connection pool open.

Position-batch is capped at 8 for a different reason. It aggregates by
`participantCurrencyId` rather than per transfer, so useful parallelism is
bounded by the number of distinct participant-currency pairs — eight, one per
FSP — not by TPS. More partitions or replicas than that can never be used.

### DFSP simulators

| Component | fsp201 | fsp202 | fsp203 | fsp204 | fsp205 | fsp206 | fsp207 | fsp208 |
|---|---|---|---|---|---|---|---|---|
| scheme-adapter | 24 | 24 | 24 | 24 | 24 | 24 | 24 | 24 |
| sim backend | 1 | 4 | 1 | 4 | 1 | 4 | 1 | 4 |
| cache | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

The sim backend is a single-threaded Node process with a roughly one-core
ceiling, and its CPU load is driven by the destination role only — payee-side
party, quote and transfer lookups. Source-only FSPs measure approximately zero
backend CPU regardless of traffic share, so only the four payees are scaled.

Redis cache `maxmemory` is 2gb. At smaller sizes the caches evict continuously
under sustained load rather than as occasional housekeeping.

## 8. Security setup (detailed)

Three independently layered mechanisms are active: edge mTLS between each DFSP
and the switch, Istio ambient mesh (ztunnel HBONE) between switch workloads,
and protocol TLS on the Kafka and MySQL connections. Crypto is ECDSA P-256
throughout — a shared lab CA and leaf at the edge (`certs/regen-certs.sh`),
istiod-issued per-workload SPIFFE certs inside the mesh
(`ECC_SIGNATURE_ALGORITHM=ECDSA` in `common/istiod-values.yaml`). TLS floor
1.2, with 1.3 auto-negotiated.

**DFSP-side mTLS is terminated by an Istio sidecar and gateway, not by the
scheme-adapter.** Each `fspNNN` cluster runs its own istiod, an inbound
Gateway, and an outbound sidecar on the scheme-adapter. This replaces the
application's inbuilt TLS on both sides: nginx SSL-passthrough on the inbound
path and the app's own `https.Agent` on the outbound path. Passthrough is
replaced because it pins a whole client connection to a single scheme-adapter
pod for the connection's lifetime, so long-lived keep-alive connections from
the switch concentrate on one pod instead of spreading across replicas.
Terminating at the sidecar lets Envoy load-balance per request.

**Prometheus scrape exemption.** A selector-scoped PeerAuthentication permits
plaintext on nine application ports (3000-3003, 3007, 4000-4002, 6060) for the
`moja` release. Ambient enrollment under a namespace-wide STRICT policy
otherwise rejects Prometheus scrapes of ambient-only pods, silently: load
continues to run while every switch-side handler histogram disappears.
Enrolled-to-enrolled traffic still negotiates mTLS — PERMISSIVE only admits a
plaintext fallback. This is a real relaxation of the posture on those ports and
is stated wherever this result is cited.

**Kafka controller and interbroker traffic is mTLS-encrypted.** At 3 brokers,
Raft consensus and replication traffic crosses the pod network between three
separate nodes, and Kafka pods are deliberately excluded from the ambient mesh
to avoid double-encrypting the client-facing SSL stream, so they get no mTLS
from that layer either. Both listeners run `protocol: SSL` with
`sslClientAuth: required` — real mutual TLS, not the client listener's
encrypt-only posture. This traffic is exclusively broker↔broker and
broker↔controller-quorum, all mutually trusted, with none of the
external-client compatibility concern that drives the client listener's
setting.

**Database TLS** is enabled encrypt-only (`db_ssl_enabled: true`,
`db_ssl_verify: false`) on every service that connects to MySQL. Certificate
verification stays off until a CA is wired into the service images.

## 9. Kafka / MySQL performance tuning

**Kafka** (3-broker combined KRaft controller+broker, RF=3, `min.insync.replicas=2`):

- Listener: SSL on port 9092 for client and external traffic. Controller and interbroker listeners: SSL with required mTLS.
- `min.insync.replicas=2` set in the top-level `kafka.extraConfig`, **not** `controller.overrideConfiguration`, which is a dead key in this chart version and silently ignored.
- `auto.create.topics.enable=false` — a client racing ahead of topic creation would otherwise create a 1-partition topic and permanently cap that stage's parallelism.
- `num.network.threads=12`, `num.io.threads=16`.
- Partition counts, matching consumer replica counts: `topic-transfer-prepare`=20, `topic-transfer-fulfil`=20, `topic-notification-event`=60, `topic-transfer-position-batch`=8, `topic-quotes-post`/`-put`/`-get`=20 each. `topic-bulkquotes-*` and `topic-fx-quotes-*` are also 20 each but carry no traffic in this workload; the remaining off-path topics keep 1 partition.
- Heap `-Xmx2g -Xms2g`, set through `controller.heapOpts`. The chart emits `KAFKA_HEAP_OPTS` from that value, so it must not also be declared in `extraEnvVars`.
- Persistence: gp3 EBS-backed PV, 200Gi per broker. Kafka's I/O is predominantly sequential — append-only log plus replication fetch and append — which fits gp3's bundled throughput rather than io2's per-IOPS pricing.
- Resources: 5/7 vCPU request/limit, 12/24Gi memory request/limit per broker.

**MySQL** (primary + 1 secondary, semi-sync replication):

- `architecture: replication` with the `rpl_semi_sync_source` / `rpl_semi_sync_replica` plugins loaded via `--plugin-load-add`. The primary blocks for the secondary's acknowledgement before the client sees a commit, for at most `rpl_semi_sync_source_timeout=1000` ms (MySQL default 10000) before falling back to asynchronous.
- `max_connections=6000`, sized above the ~5,500 summed application connection-pool maximum (`DATABASE.POOL_MAX_SIZE` × replica count) because a connection-slot ceiling fails hard rather than degrading.
- **Full per-commit durability on the primary**: `sync_binlog=1` with `innodb_flush_log_at_trx_commit=1` and `innodb_doublewrite=1`. Both the engine and the binary log are durable per transaction, so the binlog is a valid point-in-time-recovery source and a crash-recovered primary cannot be behind its own replica.
- **The secondary runs `sync_binlog=1000`, not the primary's `sync_binlog=1`.** MySQL can batch several transactions' binlog writes into one disk fsync instead of paying that cost per transaction — group commit. On the primary, concurrent client commits do this naturally. The replica cannot: `replica_preserve_commit_order` forces its applier to commit in the primary's exact order, so nothing arrives concurrently to batch, and every commit would pay its own fsync.
- `replica_parallel_workers=14` with `replica_parallel_type=LOGICAL_CLOCK`.
- `innodb_buffer_pool_size=32G` across 8 instances, `innodb_redo_log_capacity=8G`, `innodb_log_buffer_size=256M`, `innodb_flush_method=O_DIRECT`, `innodb_io_capacity=5000` / `_max=10000`.
- `binlog_expire_logs_seconds=14400`. This bounds how long the secondary may be offline before the primary purges binlogs it still needs — replication then stops with error 1236 and cannot resume without a re-seed. Size it to the longest replica outage that must survive without one.
- Persistence: io2, 200Gi per node. MySQL's commit path is frequent small synchronous writes, which is the profile io2 exists for and what makes `sync_binlog=1` affordable.
- Resources: 12/14 vCPU request/limit, 44/56Gi memory request/limit per node.
- The secondary is sized **identically** to the primary, not smaller — under semi-sync an undersized secondary throttles the primary's commit latency too, not just its own capacity.

### Kafka client tuning on the transfer path

| Setting | Value | Applies to |
|---|---|---|
| `queue.buffering.max.ms` (producer linger) | 1 | ml-api-adapter `TRANSFER.PREPARE` / `TRANSFER.FULFIL`, prepare and fulfil handlers' `TRANSFER.POSITION`, quoting-service `QUOTE.POST` / `QUOTE.PUT` |
| `queue.buffering.max.ms` | **20** | position-batch's `NOTIFICATION.EVENT` producer |
| `batch.num.messages` | 10000 | the seven producers above |
| `request.required.acks` | `all` | all producers on the transfer, quote and notification paths |
| `recursiveTimeout` | 1 | prepare, fulfil, position-batch, notification, quoting-service-handler consumers |
| `consumeTimeout` | 10 | prepare, fulfil, position-batch, notification, quoting-service-handler consumers |
| `pollIntervalMs` | 5 | the five delivery-report-emitting producers (ml-api-adapter ×2, prepare, fulfil, position-batch) |
| `syncConcurrency` | 20 | prepare, fulfil |
| `syncConcurrency` | 16 | notification |
| `batchSize` | 20 | prepare, fulfil |
| `batchSize` | 200 | position-batch, quoting-service-handler |
| `batchSize` | 100 | notification |

`topic-notification-event` has 60 partitions and is fed at twice the transfer
rate. With no producer linger, every message becomes its own
all-replicas-acknowledged produce request against a randomly chosen partition,
and the acknowledgement cost dominates the leg — measured at 626 ms mean, with
a p90 above 2 s. A 20 ms linger removes that, taking the hop's acknowledgement
to 25.8 ms. It is the one producer that needs it, being the only one combining
that partition count with that message rate.

The mechanism is coalescing produce *requests*, not filling batches: at this
partition count a flush carries only one or two messages either way, and
reducing the partition count to raise messages-per-flush does not lower
acknowledgement time further. The residual 25.8 ms is mostly the linger wait
itself, which is the floor this setting trades for.

`recursiveTimeout: 1` rather than the chart default of 100 removes a
per-message poll stall in the consumer loop worth tens of milliseconds per hop.

## 10. Deploy sequence / reproduction

```bash
SLUG=v17.3.0-mtls-mesh-2000tps

unset HTTPS_PROXY https_proxy
make terraform-init
make terraform-plan  SCENARIO=$SLUG
make terraform-apply SCENARIO=$SLUG
make tunnel          SCENARIO=$SLUG
make k8s             SCENARIO=$SLUG
make cilium          SCENARIO=$SLUG   # immediately after k8s, cluster must still be empty
make ebs-csi         SCENARIO=$SLUG   # before backend — the Kafka and MySQL PVCs need its StorageClasses
make monitoring      SCENARIO=$SLUG
make backend         SCENARIO=$SLUG
make switch          SCENARIO=$SLUG
make dfsp            SCENARIO=$SLUG
make mtls            SCENARIO=$SLUG   # after dfsp
make ambient         SCENARIO=$SLUG   # after mtls
make dfsp-monitoring SCENARIO=$SLUG
make istio-telemetry SCENARIO=$SLUG
make k6              SCENARIO=$SLUG
make onboard         SCENARIO=$SLUG
make provision       SCENARIO=$SLUG
make smoke           SCENARIO=$SLUG
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

The semi-sync check is the one that matters: with the secondary
disconnected, the primary falls back to asynchronous commits after its 1 s
timeout and the run measures a durability posture the scenario does not claim.

## 11. k6 results (full-run, unclipped)

```
checks.........................: 99.97%   ✓ 24108633    ✗ 6884
completed_transactions.........: 8031966  1986.306202/s
data_received..................: 91 GB    23 MB/s
data_sent......................: 22 GB    5.6 MB/s
discovery_time.................: avg=37.48ms  med=26ms     p(90)=77ms     p(95)=103ms   p(99)=160ms
dropped_iterations.............: 1115     0.27574/s
e2e_time.......................: avg=990.98ms med=964ms    p(90)=1.27s    p(95)=1.39s   p(99)=1.72s
failed_transactions............: 6920     1.711317/s
http_req_duration..............: avg=338.18ms med=127.37ms p(90)=891.95ms p(95)=1s      p(99)=1.25s
http_req_failed................: 0.02%    ✓ 6884        ✗ 24108633
http_reqs......................: 24115517 5963.770387/s
iteration_duration.............: avg=1.01s    med=964.19ms p(90)=1.27s    p(95)=1.39s   p(99)=1.74s
iterations.....................: 8038886  1988.017519/s
quote_time.....................: avg=139.41ms med=125ms    p(90)=212ms    p(95)=257ms   p(99)=388ms
success_rate...................: 99.91%   ✓ 8031966     ✗ 6920
transfer_time..................: avg=813.52ms med=796ms    p(90)=1.06s    p(95)=1.16s   p(99)=1.42s
vus_max........................: 4648     min=4000      max=4648
```

k6's own `status: PASSED` is evaluated against its configured thresholds
(`e2e_time p(99) < 15000`), not against this scenario's `<2s` goal.

## 12. Steady-state results

Window `2026-09-23T17:24:49Z .. 2026-09-23T18:24:49Z` (3600 s), 7,193,015
transfers measured.

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 963 ms | 1394 ms | **1727 ms** | 990 ms | 232 ms |
| transfer_time | 795 ms | 1169 ms | 1423 ms | 813 ms | 202 ms |
| quote_time | 124 ms | 256 ms | 385 ms | 139 ms | 68 ms |
| discovery_time | 25 ms | 103 ms | 159 ms | 37 ms | 31 ms |

The p99 clears the `<2s` goal by 273 ms; the median sits at 963 ms.

### Validity gate

| topic | rate |
|---|---|
| `topic-transfer-prepare` | 1999.5/s |
| `topic-transfer-fulfil` | 1998.9/s |
| `topic-transfer-position-batch` | 3998.3/s |
| `topic-notification-event` | 3997.4/s |
| `topic-quotes-post` | 1999.6/s |

`fulfil/prepare = 1.000`, `notif/prepare = 1.999`, `position-batch/prepare = 2.000` — **PASS**.

### Transfer leg breakdown

Every value is a mean over the steady window. A transfer traverses six Kafka
hops: three on the prepare half and three on the fulfil half. `transit` is the
interval from the producing handler's produce call to the consuming handler
starting work, and decomposes as `fetch_wait + produce_ack + queue_wait`.

| # | topic → consumer | transit | fetch_wait | produce_ack | queue_wait | handler |
|---|---|---|---|---|---|---|
| 1 | `transfer-prepare` → prepare | 44.6 | 31.1 | 12.9 | 0.7 | 42.1 |
| 2 | `position-batch` → position-batch | 87.4 | 71.4 | 14.2 | 1.8 | 69.3 |
| 3 | `notification-event` → notification | 128.1 | 48.1 | 25.8 | 54.2 | 22.3 |
| 4 | `transfer-fulfil` → fulfil | 42.8 | 27.5 | 14.8 | 0.6 | 36.1 |
| 5 | `position-batch` → position-batch | 87.4 | 71.4 | 14.2 | 1.8 | 69.3 |
| 6 | `notification-event` → notification | 128.1 | 48.1 | 25.8 | 54.2 | 22.3 |
| | **total** | **518.5** | **297.5** | **107.7** | **113.3** | **261.7** |

Summed against a measured transfer leg of 817.9 ms, this accounts for 95% of
it; the 37.8 ms residual is the DFSP payee turnaround plus the HTTP edges
outside any switch span.

- **`fetch_wait` is the largest single component** — 297.5 ms, 36% of the leg.
- **Position-batch accounts for about half of `fetch_wait`** — 71.4 ms per hop, on both of its hops.
- **The two notification hops cost 256 ms of transit between them**, the largest transit share of any stage.
- **45% of the handler bucket is not switch compute.** The notification handler's 22.3 ms is 20.2 ms of outbound HTTP callback to the DFSP, and prepare's 42.1 ms and fulfil's 36.1 ms are write-path database time.
- Position-batch processes 83.1 messages per batch against a `batchSize` cap of 200, so the cap is not binding.

### MySQL and replication under load

- Semi-sync engaged for the entire run: `Rpl_semi_sync_source_status` ON, `Rpl_semi_sync_source_no_tx` **0** — no commit fell back to asynchronous.
- The primary commits roughly 4.2 database transactions per transfer.
- The replica applier runs behind under load and drains afterwards. Lag peaked in the low hundreds of seconds and reached zero about ten minutes after load stopped — an observed RTO under 10 minutes for a 67-minute run at this rate. RPO is unaffected: semi-sync acknowledges on relay-log receipt, not on apply.
- **Measure drain progress by GTID delta, not `Seconds_Behind_Source`.** It is `now` minus the timestamp of the event being applied, so it climbs by one second per wall-clock second while the actual backlog shrinks, then drops to zero in one step. The delta between `Retrieved_Gtid_Set` and `Executed_Gtid_Set` tracks the real backlog.
- All 14 applier workers are occupied under load while the secondary uses only ~2.9 of 16 vCPU, so the applier is not CPU-bound. Parallelism is bounded by write-set conflicts: every transfer updates one of only ~8 `participantPosition` rows, which forces those transactions into a small number of dependent chains regardless of worker count.

## 13. Capacity used

Steady-window averages. Nothing is saturated.

| Node | avg CPU | peak CPU |
|---|---|---|
| Switch application nodes (20) | 50.2 – 63.0% | 51.6 – 65.2% |
| `sw1-kafka-n1` / `-n2` / `-n3` | 58.1 / 57.1 / 57.2% | 59.7 / 58.4 / 58.5% |
| `sw1-mysql-n1` (primary) | 61.4% | 62.5% |
| `sw1-mysql-n2` (secondary) | 30.6% | 31.4% |
| `sw1-monitoring` | 10.5% | 11.1% |

DFSP simulator nodes:

| Node | avg CPU | peak CPU | Role |
|---|---|---|---|
| `fsp204` | 75.4% | 81.1% | payee |
| `fsp208` | 74.2% | 75.6% | payee |
| `fsp206` | 71.3% | 75.4% | payee |
| `fsp203` | 70.9% | 79.9% | payer |
| `fsp202` | 69.2% | 70.3% | payee |
| `fsp207` | 66.4% | 67.4% | payer |
| `fsp201` | 61.5% | 63.2% | payer |
| `fsp205` | 60.7% | 65.2% | payer |

The DFSP simulators are the most heavily loaded machines in the rig — more so
than any switch node. They are test harness, not system under test, so this is
a measurement-fidelity consideration rather than a Mojaloop capacity finding.

## 14. Caveats, concessions, known limitations

- **`db_ssl_verify` on `als-msisdn-oracle`** is applied by configmap patch rather than Helm values, because the chart renders it as the truthy string `"false"`, which breaks the knex migration init container.
- **0.086% of transfers failed** (6,920 of 8,038,886), with 6,310 of those on `POST /transfers`. The slowest requests hit a 30 s ceiling, indicating a timeout rather than a rejection.

## 15. Other observations / gotchas found

### Deviations from the stock charts

- **`min.insync.replicas`** must be set in the top-level `kafka.extraConfig`. The chart exposes `controller.overrideConfiguration`, which is silently ignored at this version.
- **Kafka heap** must be set via `controller.heapOpts`. The chart already emits `KAFKA_HEAP_OPTS` from that value, so declaring it again in `extraEnvVars` fails server-side apply with a duplicate-key error.
- **`#` characters inside a `extraFlags: |` block are not comments.** The block is passed through as mysqld argv, and a `#` line becomes an argument — mysqld then exits with `Too many arguments`. Rationale comments must sit above the block.
- **The secondary must not set `--super_read_only=ON`.** The bitnami entrypoint runs a housekeeping `DELETE FROM mysql.user` during bootstrap as root; `super_read_only` blocks it even for SUPER-privileged connections, so the entrypoint aborts before configuring replication and the container never gets a valid local root credential. `--read_only=ON` alone gives the intended protection.
- **`MYSQL_REPLICATION_SLAVE_DUMP=true`** is required on the secondary and is not a first-class Helm value — it goes through `secondary.extraEnvVars`. Without it a fresh secondary never receives the primary's `mysql` system schema, and its root row is never restored. Helm replaces list-valued keys wholesale across values files rather than merging them, so this entry must be repeated in every values file that defines `secondary.extraEnvVars`.
- **`secondary.startupProbe.failureThreshold`** must be widened well past the chart default for that one-time dump to finish once the primary holds real data. A container killed mid-dump freezes in a half-initialised state permanently, because every subsequent restart takes the fast persisted-data path and never retries.
- **Central-ledger v20.x ships only `dist/`.** Any deployment pinned to a v20 image needs an explicit `command:` override, because the chart's default commands target `src/`, which exists only in v19.x.
- **Position-batch's configmap needs 13 resolver-asserted keys** that older versions did not require: `HANDLERS.TIMEOUT.DIST_LOCK`, `HANDLERS.SETTINGS.RULES`, `WINDOW_AGGREGATION`, `ENABLE_ON_US_TRANSFERS`, `KAFKA.CONSUMER.NOTIFICATION`, `KAFKA.CONSUMER.DEFERREDSETTLEMENT`, and seven `KAFKA.EVENT_TYPE_ACTION_TOPIC_MAP.POSITION` sub-keys. Position-batch is the handler that reads that topic map, so incomplete abort and timeout routing is a correctness gap independent of startup.

## 16. Dashboard screenshots

Not yet captured for this scenario.
