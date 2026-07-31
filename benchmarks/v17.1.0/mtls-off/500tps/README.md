# v17.1.0 / mtls-off / 500tps — Scenario Report

This scenario runs the Mojaloop switch with no encryption anywhere on the
transaction path — no edge mTLS, no Kafka/MySQL protocol TLS, no pod-pod
encryption of any kind — establishing a zero-security-cost baseline. It
also carries this hardware's max-sustainable-TPS exploration: the same
5-node switch cluster is pushed past its 500 TPS design target to find
where the `<1s` steady-state e2e p99 goal actually breaks, independent of
any encryption cost.

## 1. Scenario

- **Version:** v17.1.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 650 TPS, 13 FSP pairs (4 source FSPs → 4 destination FSPs)
- **Status:** ✅ **PASS** — steady-state e2e p99 = **946ms** (<1s goal) at **650 TPS**, the verified maximum for this hardware. The 500 TPS design target passes with ~30% node-CPU margin; 700 TPS sustains cleanly (99.94% success) but misses the goal at p99 ≈ 1.06s.

## 2. Test methodology & definitions

- **Steady-state window:** start+5min .. end−2min (TPC/SPEC-style warm-up/drain trim). The k6 end-of-run summary is always the full-run aggregate; steady-state is the authoritative number for pass/fail (full-run p99 1008ms vs steady 946ms here — the difference is ramp-up/ramp-down edge effects).
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0. This run: **PASS, exact** (1.000 / 2.000).
- **Tooling:** `benchmarks/tools/steady-state.sh` (Prometheus-driven).

## 3. Test design parameters

- **Target TPS:** 650
- **Target transaction count:** 1,273,000 (1,000,000 measured in steady state + 273,000 in the 5-min warm-up/2-min drain)
- **Transfer amount / currency:** 1 XXX
- **Duration:** ~1978s (~33 min)
- **Test load distribution** `overrides/k6.yaml`

| Source (Payer) | → fsp202 | → fsp204 | → fsp206 | → fsp208 | Total generated |
|---|---|---|---|---|---|
| fsp201 (large) | 49% | 7% | 7% | 7% | **70%** |
| fsp203 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| fsp205 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| fsp207 (small) | – | 3.33% | 3.33% | 3.33% | **10%** |
| **Total received** | **49%** | **17%** | **17%** | **17%** | **100%** |

fsp201 alone generates 70% of total load — deliberately skewed to stress one large source FSP against three smaller ones (each generating 10%, split evenly across the same three destinations), matching a realistic hub-and-spoke traffic pattern. Only fsp202 receives exclusively from fsp201; fsp204/206/208 each receive a mix from all four source FSPs.

## 4. Hardware / infrastructure

| Role | Count | Instance type | Notes |
|---|---|---|---|
| Switch (generic) | 5 | m7i.2xlarge (8 vCPU/32GiB) | sw1-n1..n5 |
| Kafka | 1 | m7i.xlarge (4 vCPU/16GiB) | sw1-kafka-n1 |
| MySQL | 1 | m7i.xlarge (4 vCPU/16GiB) | sw1-mysql-n1 |
| Monitoring | 1 | m6i.large | |
| DFSP fsp201, fsp202 | 2 | c7i.2xlarge | primary traffic-generating FSPs (70% + 49% combined weight) |
| DFSP fsp203-208 | 6 | c7i.xlarge | |
| k6 | 1 | m7i.2xlarge | |
| Bastion | 1 | t3.small | |

- **AZ / placement:** eu-west-2b, cluster placement group (lowest inter-node latency)

### Cluster architecture (MicroK8s)

10 isolated MicroK8s clusters (v1.32/stable) on one AWS VPC (`10.112.0.0/16`), private subnet, each with its own control plane.

**Switch cluster** (`mojaloop-switch`, 8 nodes: sw1-n1..n5, kafka, mysql, monitoring)
- Runs Mojaloop core services, Kafka, MySQL, Prometheus/Grafana.
- All 8 nodes are full MicroK8s/dqlite members. Workload placement (keeping app pods off Kafka/MySQL/monitoring) is enforced by node taints/labels (§5), not by a control-plane/worker split.
- Addons: `dns`, `storage`, `ingress`, `metrics-server`.
- Networking: pod CIDR `10.1.0.0/16` (Cilium IPAM), service CIDR `10.96.0.0/12`, cluster DNS `10.96.0.10`.

**DFSP clusters** (`fsp201`..`fsp208`, 1 node each, 8 clusters total)
- Each runs mojaloop-simulator + sdk-scheme-adapter for that one DFSP.
- Single-node: the one node is both control-plane and worker.
- Same addons as the switch cluster.

**k6 cluster** (1 node)
- Runs the k6 Operator + test runner pods.

**Cross-cluster networking:** each cluster is independent with its own `.local` domain and no shared DNS — resolution across clusters is wired by hand via CoreDNS ConfigMap patches + Kubernetes `hostAliases` (k6 → DFSP node IPs, each DFSP → the switch cluster's internal NLB, switch → DFSP node IPs). No public internet is involved: all switch, DFSP, and k6 nodes sit in one private subnet (`10.112.2.0/24`) within the same VPC; only the bastion has a public IP (separate public subnet, `10.112.1.0/24`), used solely for operator SSH access. Security groups restrict cluster nodes to traffic from the bastion (SSH/admin) or from each other (`source: self`) — nothing external can reach them, and there's no route out to the public internet. Cross-cluster traffic is plain private-IP routing over the VPC's internal network fabric; the switch's NLB is `scheme: internal`, not internet-facing.

## 5. System-level overrides

- **Kernel pin:** `6.17.0-1013-aws` on switch nodes — the stock AMI kernel (GA 6.8) runs ~10% higher softirq than 6.17 under sustained load. Installed + grub-configured pre-MicroK8s so the reboot is safe.
- **Node taints/labels:** `workload-class.mojaloop.io/*` labels partition switch-node scheduling (all 5 generic nodes carry the same label set); Kafka/MySQL/monitoring nodes are tainted `dedicated=kafka|mysql|monitoring:NoSchedule` to keep app pods off them.

### CNI / Cilium setup

Cilium **replaces** MicroK8s' default Calico dataplane: Calico's iptables/veth dataplane re-injects packets at ~12x the wire packet rate under sustained load, saturating switch-node softirq; Cilium's eBPF native-routing dataplane avoids this.

| Setting | Value | Purpose |
|---|---|---|
| Version | 1.17.1 | matches MicroK8s 1.32 channel |
| Mode | eBPF **native routing** (no overlay/VXLAN) | zero encapsulation overhead — all switch nodes share one L2 subnet |
| `kube-proxy-replacement` | **false** | coexists with MicroK8s' embedded kube-proxy |
| `socketLB` | **on** | eBPF pod→ClusterIP redirection at `connect()` |
| BPF masquerade / host routing | eBPF (native) | fast path enabled |
| hostPort / NodePort | **on** (`enable-host-port`, `enable-node-port`) | serves the nginx ingress (:80) DaemonSet |
| **Encryption** | **disabled** | this scenario's defining setting — no pod-pod encryption of any kind |
| Hubble | on | flow visibility |

## 6. Helm chart versions + values overrides

- **Chart versions:** mojaloop=17.1.0, backend=17.1.0, simulator=15.10.0
- **Key overrides:**
  - `overrides/mojaloop.yaml` — replica counts per §7 below; `log_level: info` on all services
  - `overrides/backend.yaml` — plaintext Kafka + plaintext MySQL; broker/DB tuning per §9 (`max_connections=1500`, MySQL CPU limit 4.0, Kafka CPU limit 3.5)
  - `overrides/aws.yaml` — node sizing per §4
  - `overrides/dfsp.yaml` — DFSP simulator replica counts per §7

## 7. Pod distribution & replica counts

| Service | Replicas |
|---|---|
| account-lookup-service | 10 |
| account-lookup-service-admin | 1 |
| als-msisdn-oracle | 8 |
| centralledger-service | 8 |
| centralledger-handler-transfer-prepare | 12 |
| centralledger-handler-transfer-fulfil | 12 |
| centralledger-handler-transfer-get | 1 |
| centralledger-handler-admin-transfer | 1 |
| centralledger-handler-timeout | 1 |
| handler-pos-batch (transfer-position/position-batch) | 8 |
| centralsettlement-service | 1 |
| centralsettlement-handler-rules | 1 |
| centralsettlement-handler-deferredsettlement | 1 |
| quoting-service | 12 |
| quoting-service-handler | 12 |
| ml-api-adapter-service | 12 |
| ml-api-adapter-handler-notification | 18 |
| transaction-requests-service | 1 |
| ml-testing-toolkit-backend / -frontend | 1 each |
| ttk-mongodb | 1 |
| kafka-controller | 1 (StatefulSet) |
| mysqldb | 1 (StatefulSet) |

Notification handler (18) is deliberately the highest-replica service — it's the consumer most exposed to backpressure (2× the prepare rate: one notification per prepare AND one per fulfil).

**DFSP simulators** (per FSP cluster, `fsp201`–`fsp208`) — `overrides/dfsp.yaml`:

| Component | fsp201 / fsp202 | fsp203–fsp208 |
|---|---|---|
| mojaloop-simulator | 2 | 1 |
| sdk-scheme-adapter | 16 | 4 |

`fsp201`/`fsp202` get 4x the scheme-adapter replicas of the other 6 — they carry the heaviest share of the FSP pair load (see §3's source×destination matrix). fsp201/fsp202's sim backends run 2 replicas each because they receive the bulk of all traffic (70%/49%) through a component that is otherwise a single-threaded Node process (§15).

Pod-to-node spread across the 5 generic nodes is scheduler-determined per service (topologySpreadConstraints, maxSkew=1); the cross-service aggregate can still concentrate on one node (§15).

## 8. Security setup (detailed)

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (edge, both directions) | **None** — plain HTTP both directions |
| service ↔ service (app pods) | **None** |
| apps ↔ Kafka | **None** — plaintext listener |
| apps ↔ MySQL | **None** — plaintext (`mysql.tls.enabled: false`; server still *offers* TLS via the chart's `MYSQL_ENABLE_SSL` default, but no application client requests it) |
| Pod-pod encryption | **None** — Cilium WireGuard disabled, no service mesh deployed |

This is the deliberate floor: every byte on the transaction path travels
unencrypted inside the private VPC. Network isolation (private subnet,
security groups, internal-only NLB — §4) is the only protection. Every other
security configuration's overhead is measured relative to this baseline.

### Traffic flow — DFSP → switch (inbound)

1. The DFSP scheme-adapter makes a plain HTTP call to `<service>.local:80`.
2. Cross-cluster CoreDNS resolves the `.local` hostname to the switch's internal NLB.
3. NLB (:80) → NodePort 30080 → the nginx ingress DaemonSet → the in-cluster Service (account-lookup-service, quoting-service, or ml-api-adapter).

### Traffic flow — switch → DFSP (outbound)

1. The switch services (account-lookup-service, quoting-service-handler, the notification handler) make plain HTTP calls to `http://sim-fspNNN.local/...`.
2. `sim-fspNNN.local` resolves via a `hostAliases` entry (refreshed from the live DFSP node IPs on every deploy) directly to the target DFSP node.
3. The DFSP's nginx ingress routes to the scheme-adapter's inbound API over HTTP.

## 9. Kafka / MySQL performance tuning

**Kafka** (single-broker KRaft, RF=1 everywhere — see §14 for why):
- Plaintext listener on port 9092
- CPU limit 3.5 (of 4 vCPU on its dedicated node)
- `auto.create.topics.enable=false` with the full provisioning topic list — a client racing ahead of provisioning would otherwise create a topic at 1 partition, silently stranding a consumer group sized for N partitions
- Partition counts (validity-gate topics): `topic-transfer-prepare`=12, `topic-transfer-fulfil`=12, `topic-notification-event`=18, `topic-transfer-position-batch`=8, `topic-quotes-post`=12
- `num.network.threads=12`, `num.io.threads=16`, `queued.max.requests=2000`
- `log.segment.bytes=16MB` + `log.segment.ms=60000` + `log.retention.ms=300000` (5min) — retention continuously trims closed segments, keeping broker memory/disk flat instead of growing unbounded
- JVM: G1GC, `MaxGCPauseMillis=20`

**MySQL** (single instance, ephemeral storage — see §14):
- `max_connections=1500` — every service replica holds its own connection pool (`POOL_MAX_SIZE` up to 30 each); with ~43 central-ledger replicas alone the aggregate idle-pool demand approaches 1000 connections while `threads_running` stays under 40, so the ceiling must budget for pool slots, not query concurrency
- CPU limit 4.0 (the full dedicated 4-vCPU node) — CFS quota throttling at lower limits clips sub-second bursts that node-level utilization averages hide
- `innodb_buffer_pool_size=8G` (8 instances), `innodb_redo_log_capacity=2G`
- `innodb_flush_log_at_trx_commit=2` + `sync_binlog=0` — relaxed durability for throughput (fsyncs decoupled from per-commit writes)
- `innodb_io_capacity=3000` / `_max=6000`, `innodb_doublewrite=0`
- `thread_cache_size=100`, `table_open_cache=4000`
- `performance_schema=OFF`, `skip_name_resolve=ON`

## 10. Deploy sequence / reproduction

Run steps individually (not the composite deploy) — this scenario skips the
mTLS and Istio-telemetry stages entirely:

```bash
SLUG=v17.1.0-mtls-off-500tps
make terraform-plan  SCENARIO=$SLUG    # regenerate plan against current state + aws.yaml
make terraform-apply SCENARIO=$SLUG
make tunnel          SCENARIO=$SLUG    # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s             SCENARIO=$SLUG
make cilium          SCENARIO=$SLUG EXTRA='-e cilium_encryption_enabled=false'
make monitoring      SCENARIO=$SLUG
make backend         SCENARIO=$SLUG
make switch          SCENARIO=$SLUG    # also exposes nginx :80 (NodePort 30080)
make dfsp            SCENARIO=$SLUG    # pure sims, plain HTTP
make dfsp-monitoring SCENARIO=$SLUG
make k6              SCENARIO=$SLUG
make onboard         SCENARIO=$SLUG
make provision       SCENARIO=$SLUG
make smoke           SCENARIO=$SLUG    # GATE — a plain-HTTP transfer must COMPLETE
make load            SCENARIO=$SLUG
```

⚠️ At the smoke test: onboarding must register DFSP callback endpoints as
`http://` (not https) — if the smoke transfer fails on transport, check
`onboard.yaml`.

## 11. k6 results (full-run, unclipped)

Full-run e2e p99 1008ms, 99.97% success. Raw k6 end-of-run summary:

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 1272880 / ✗ 40
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 1272878 / ✗ 2
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 1272513 / ✗ 365

   ✓ checks.........................: 99.98%  ✓ 3818271     ✗ 407
   ✓ completed_transactions.........: 1272513 644.072929/s
     data_received..................: 8.6 GB  4.3 MB/s
     data_sent......................: 3.6 GB  1.8 MB/s
   ✓ discovery_time.................: avg=25.38ms  min=1ms      med=20ms     max=2.79s   p(90)=42ms     p(95)=55ms     p(99)=90ms
     dropped_iterations.............: 431     0.218147/s
   ✓ e2e_time.......................: avg=647.6ms  min=200ms    med=634ms    max=13.56s  p(90)=804ms    p(95)=859ms    p(99)=1s
     failed_transactions............: 407     0.206/s
     http_req_blocked...............: avg=3.34µs   min=660ns    med=2.09µs   max=8.47ms  p(90)=4.18µs   p(95)=4.95µs   p(99)=10.42µs
     http_req_connecting............: avg=543ns    min=0s       med=0s       max=7.06ms  p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=218.75ms min=668.16µs med=123.68ms max=30.04s  p(90)=541.15ms p(95)=602.28ms p(99)=713.19ms
       { expected_response:true }...: avg=215.62ms min=1.14ms   med=123.66ms max=11.87s  p(90)=541.06ms p(95)=602.12ms p(99)=712.52ms
     http_req_failed................: 0.01%   ✓ 407         ✗ 3818271
     http_req_receiving.............: avg=25.44µs  min=8.14µs   med=22.98µs  max=3.86ms  p(90)=36.4µs   p(95)=41.63µs  p(99)=54.79µs
     http_req_sending...............: avg=17.46µs  min=3.74µs   med=10.01µs  max=21.48ms p(90)=15.67µs  p(95)=20.73µs  p(99)=55.63µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=218.7ms  min=645.69µs med=123.64ms max=30.04s  p(90)=541.12ms p(95)=602.24ms p(99)=713.15ms
     http_reqs......................: 3818678 1932.795284/s
     iteration_duration.............: avg=657.14ms min=14.44ms  med=634.26ms max=37.18s  p(90)=804.89ms p(95)=859.37ms p(99)=1.01s
     iterations.....................: 1272920 644.278929/s
   ✓ quote_time.....................: avg=128.62ms min=33ms     med=123ms    max=11.87s  p(90)=197ms    p(95)=219ms    p(99)=259ms
   ✓ success_rate...................: 99.96%  ✓ 1272513     ✗ 407
   ✓ transfer_time.................: avg=493.29ms min=146ms    med=484ms    max=6.37s   p(90)=632ms    p(95)=678ms    p(99)=792ms
     vus............................: 20      min=0         max=1411
     vus_max........................: 1425    min=1000      max=1425
```

## 12. Steady-state results

| metric | value |
|---|---|
| e2e p50 | 630ms |
| e2e p95 | 846ms |
| **e2e p99** | **946ms** |
| e2e stddev | 122ms |
| transfer p99 | 755ms |
| quote p99 | 249ms |
| discovery p99 | 79ms |
| steady transfers measured | 1,012,461 |
| validity gate | PASS (fulfil/prepare=1.000, notif/prepare=2.000) |

**Rate sweep on the same configuration:** 500 TPS → p99 831ms (~30% node-CPU
margin); 650 TPS → 946ms (this run — the verified maximum under 1s); 700 TPS →
sustains 699 actual TPS at 99.94% success but p99 ≈ 1.06-1.15s across two
placements, over the goal. The 650→700 miss is diffuse queueing (every switch
and heavy-DFSP node at 75-90%), not any single saturated component.

## 13. Capacity used

**Node CPU (steady window):**

| node | avg | peak |
|---|---|---|
| sw1-n1 | 74.8% | 75.8% |
| sw1-n2 | 67.7% | 68.7% |
| sw1-n3 | 69.9% | 71.5% |
| sw1-n4 | 75.4% | 76.6% |
| sw1-n5 | 81.8% | 83.5% |
| kafka | 66.0% | 66.6% |
| mysql | 69.8% | 70.3% |
| monitoring | 24.5% | 45.5% |

**DFSP node CPU (steady window, avg):** fsp201 76.4%, fsp202 72.1%,
fsp206 54.3%, fsp208 46.9%, fsp204 46.2%, fsp203/205/207 ≈ 30%.

**Headroom assessment:** at 650 TPS the hottest switch node (n5) runs 81.8%
avg and the hottest DFSP (fsp201, the 70% source) 76.4% — both sides of the
system reach their queueing knee together at ~700 TPS, where p99 crosses 1s
with no individual component saturated. Raising the ceiling further requires
hardware on both the switch side and the two heavy DFSP nodes.

## 14. Caveats, concessions, known limitations

- **Kafka RF=1, single broker (KRaft)** — no replication, no HA. Acceptable for a throughput benchmark; not a production posture.
- **MySQL: single instance, ephemeral storage (`persistence.enabled: false`)** — no HA, no durability across pod restart. `sync_binlog=0` + `innodb_flush_log_at_trx_commit=2` trade a small durability window for throughput.
- **Plaintext is the point, not an oversight** — this configuration exists as the comparison floor; it is not a deployable security posture for a financial switch.
- **DFSP replica counts come from `overrides/dfsp.yaml`** (`dfsp_backend_replicas`, `dfsp_sdk_replicas_*` — ansible vars, not forwarded to Helm) — the simulator chart cannot express per-component replicas, so the dfsp role scales imperatively.
- **Sim backends must be restarted before each measurement campaign** — see §15; their in-memory databases grow without bound across runs.
- **`log_level: info` on all switch services** — a known CPU/GC cost near saturation; kept for parity across all measured configurations.

## 15. Other observations / gotchas found

Findings from this scenario worth carrying to any reproduction (several are
general Mojaloop-perf-testing landmines, discovered here because the plaintext
configuration was the first pushed past its design target):

- **The mojaloop-simulator backend's in-memory database grows without bound across runs** (`MODEL_DATABASE: ':memory:'`). Each 1.27M-transfer run adds ~500MB of working set to every *destination* FSP's backend. Past ~2.5GB, Node garbage-collection pauses reach seconds (multi-second stalls appear in all three legs, since the payee backend serves discovery, quotes, and transfers); at ~3.9GB the process dies with a heap OOM and its **registered parties die with it** — the FSP then fails 100% of lookups until re-onboarded, while the pod itself reports Running/Ready. Restart all sim backends (and re-onboard/provision) before every measurement run.
- **The sim backend is a single-threaded Node process with no log-level knob and no chart-level replica control.** At ~1 core of demand it becomes an invisible ceiling: no instrumentation exists on the DFSP side, so it manifests only as unexplained client-side tail latency while every switch metric stays clean. Diagnose via per-container CPU (`rate(container_cpu_usage_seconds_total)` peaks approaching 1.0).
- **MySQL's limit is connection *slots*, not query throughput.** With every service replica holding a `POOL_MAX_SIZE`-deep idle pool, `threads_connected` approached the 1000 default while `threads_running` never exceeded 40 — the failure mode is connection-refused storms that collapse all legs at once, at *lower* node CPU than a healthy run. Budget `max_connections` for aggregate pool demand (replicas × pool size), or shrink the per-replica pools.
- **CFS throttling metrics must be read per-container, not per-pod.** The Kafka pod's jmx-exporter sidecar (0.375-core limit) throttles constantly and dominates the pod-level number; the broker container itself throttled 0%. Attributing sidecar throttling to the main container leads to unnecessary limit increases.
- **Per-service topologySpreadConstraints do not prevent cross-service aggregate skew.** Every heavy service satisfied maxSkew=1 individually while all of their "remainder" pods stacked on the same node (~15-20 CPU points hotter than the coolest peer). Manual rebalancing relocates the hotspot rather than dissolving it (verified across three placements); at 650 TPS placement made no measurable p99 difference (946-974ms across three spreads), at 700 TPS it was worth ~90ms — never enough to change a verdict.

## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/` (10 dashboards, from
the recorded run's window, 2026-07-13 20:35–21:09 UTC). The two mesh-specific
dashboards (mTLS/Mesh Overhead, Service Mesh Hop Latency) are deliberately
omitted — there is no mesh in this configuration. Representative panels:

**Capacity & Saturation** — node CPU/pressure/memory per node; matches the §13 table (hottest node sw1-n5 at ~82%)
![Capacity & Saturation](<screenshots/Capacity & Saturation/Capacity & Saturation - 1.png>)

**K6 Transaction Latency (client-observed)** — the SLA-gate metric (steady e2e p99 946ms)
![K6 e2e latency](<screenshots/K6 Transaction Latency (Client-Observed)/K6 Transaction Latency (Client-Observed) - 1.png>)

**Kafka - Whitepaper Overview** — validity-gate topic rates (650/1300 per §12) and consumer lag
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**MySQL Overview** — command breakdown, redo-log activity, buffer pool, connections (peak well inside the 1500 limit)
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**FSP / DFSP Simulator — Capacity**
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Mojaloop - Central-Ledger - Performance Characterization**
![Central-Ledger Characterization](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

Additional captures (Central Ledger transfer legs, ALS, Quoting Service,
ML-API Adapter) are in their respective `screenshots/` subfolders.
