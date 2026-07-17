# v17.1.0 / mtls-mesh / 500tps — Scenario Report

_See `results/<run>/MANIFEST.md` + `summary.json` for raw per-run
data, and `screenshots/` for dashboard captures. This file consolidates
everything else — setup, deploy sequence, results, chart deviations — into
a single scenario reference._

## 1. Scenario

Scenario:
**mTLS + full service mesh** — every byte on the transaction path encrypted,
using workload-identity mTLS for app-to-app traffic and native protocol TLS
for datastores.

- **Version:** v17.1.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 500 TPS, 13 FSP pairs (4 source FSPs → 4 destination FSPs)
- **Status:** ✅ **PASS** — steady-state e2e p99 = **910ms** (<1s goal)

## 2. Test methodology & definitions

- **Steady-state window:** start+5min .. end−2min (TPC/SPEC-style warm-up/drain trim). The k6 end-of-run summary is always the full-run aggregate; steady-state is the authoritative number for pass/fail. Full-run p99 is materially higher than steady-state here (963ms vs 910ms) purely from ramp-up/ramp-down edge effects — not a real regression.
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0, position-batch/prepare ≈ 2.0. Both runs: **PASS**.

## 3. Test design parameters

- **Target TPS:** 500
- **Target transaction count:** 1,210,000 (1,000,000 measured in steady state + 210,000 in the 5-min warm-up/2-min drain)
- **Transfer amount / currency:** 1 XXX
- **Duration:** ~2420s (~40 min) per run
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
- **Node taints/labels:** `workload-class.mojaloop.io/*` labels partition switch-node scheduling (CORE-API-ADAPTERS, CENTRAL-LEDGER-SVC, ALS-ORACLES, etc. — all 5 generic nodes carry the same label set, i.e. no per-node service pinning by default); Kafka/MySQL/monitoring nodes are tainted `dedicated=kafka|mysql|monitoring:NoSchedule` to keep app pods off them — this taint is what actually enforces the intended workload split, not cluster membership (see cluster architecture above).

### CNI / Cilium setup

Cilium **replaces** MicroK8s' default Calico dataplane: Calico's iptables/veth dataplane re-injects packets at ~12x the wire packet rate under sustained load, saturating switch-node softirq; Cilium's eBPF native-routing dataplane avoids this.

| Setting | Value | Purpose |
|---|---|---|
| Version | 1.17.1 | matches MicroK8s 1.32 channel |
| Mode | eBPF **native routing** (no overlay/VXLAN) | zero encapsulation overhead — all switch nodes share one L2 subnet |
| `kube-proxy-replacement` | **false** | coexists with MicroK8s' embedded kube-proxy |
| `socketLB` | **on**, `hostNamespaceOnly: true` | eBPF pod→ClusterIP redirection at `connect()` |
| BPF masquerade / host routing | iptables / legacy | ambient/ztunnel compatibility |
| hostPort / NodePort | **on** (`enable-host-port`, `enable-node-port`) | serves the istio-ingressgateway (:443) and nginx (:80) DaemonSets |
| `cni.exclusive` | **false** | allows `istio-cni` to chain after Cilium |
| Hubble | on | flow visibility |

## 6. Helm chart versions + values overrides

- **Chart versions:** mojaloop=17.1.0, backend=17.1.0, simulator=15.10.0
- **Key overrides:**
  - `overrides/mojaloop.yaml` — replica counts per §7 below; `log_level: info` on all services
  - `overrides/backend.yaml` — Kafka SSL-only listener + tuning, MySQL TLS + tuning (full detail in §9)
  - `overrides/aws.yaml` — node sizing per §4 (shared infra — provisioned once, reused across scenarios)
  - Mesh (ambient mTLS, STRICT PeerAuthentication) is configured outside the Helm chart values entirely (see §8)

## 7. Pod distribution & replica counts

| Service | Replicas |
|---|---|
| account-lookup-service | 8 |
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

**DFSP simulators** (per FSP cluster, `fsp201`–`fsp208`):

| Component | fsp201 / fsp202 | fsp203–fsp208 |
|---|---|---|
| mojaloop-simulator | 1 | 1 |
| sdk-scheme-adapter | 16 | 4 |

`fsp201`/`fsp202` get 4x the scheme-adapter replicas of the other 6 — they carry the heaviest share of the FSP pair load (see §3's source×destination matrix).

Notification handler (18) is deliberately the highest-replica service — it's the consumer most exposed to backpressure (2× the prepare rate: one notification per prepare AND one per fulfil).

Pod-to-node spread across the 5 generic nodes is scheduler-determined (no explicit topologySpreadConstraints beyond default). See the Capacity & Saturation dashboard screenshots for the node-CPU distribution actually measured.

## 8. Security setup (detailed)

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (edge, both directions) | Istio **sidecar** mTLS on the 3 egress deployments + ingressgateway, file-mounted certificates |
| service ↔ service (app pods) | Istio **ambient mesh** — per-node ztunnel proxies carry HBONE mTLS between all enrolled pods, istiod-issued SPIFFE workload identities. **STRICT** PeerAuthentication across the mojaloop namespace |
| apps ↔ Kafka | **Kafka protocol TLS** (SSL-only listener, encrypt-only: `sslClientAuth: none`, no client certs). Broker **un-enrolled from the mesh** (`istio.io/dataplane-mode: none`) to avoid double-encrypting |
| apps ↔ MySQL | **MySQL protocol TLS**, encrypt-only, same un-enrolled-from-mesh treatment |
| Other datastores | Mongo/Redis removed from this profile (no clients use them here); `ttk-mongodb` kept solely for the Testing Toolkit's own dependency |
| Pod-pod encryption | Ambient (app-to-app) + protocol TLS (datastores) fully cover it |

Net posture: every byte on the transaction path is encrypted — apps get workload-identity-verified mTLS via the mesh, datastores get transport-layer TLS, edge traffic gets sidecar mTLS. 100% of traffic (`istio_requests_total{reporter="destination"}`) is `connection_security_policy=mutual_tls`.

### Cryptography

| Domain | Certificate | Algorithm | TLS version | Cipher suites / curves |
|---|---|---|---|---|
| DFSP ↔ switch edge (both directions) | Single shared lab CA + leaf cert, SANs covering all 3 switch service hostnames and all 8 DFSP simulator hostnames; the same leaf is used as both server and client cert in both directions | ECDSA P-256 | 1.2 floor, 1.3 negotiated automatically when both peers support it | ECDHE-ECDSA-AES128-GCM-SHA256, ECDHE-ECDSA-AES256-GCM-SHA384; X25519, P-256 |
| service ↔ service (ambient mesh) | istiod-issued, per-workload SPIFFE identity certificates, auto-rotated (24h default) | ECDSA P-256 | Mesh-internal default (left un-pinned, so it keeps accepting both RSA and ECDSA peers through any future cert rotation) | Mesh-internal default |

The edge cert's key usage is `digitalSignature` only (no static-ECDH `keyAgreement`) since ECDSA here signs the handshake under ECDHE — key agreement itself is negotiated separately via the curves above.

### Traffic flow — DFSP → switch (inbound)

1. The DFSP scheme-adapter opens a TLS connection to `<service>.local:443`, presenting its client certificate (the same shared CA/leaf, mounted on the DFSP side).
2. Cross-cluster CoreDNS resolves the `.local` hostname to the switch's real node IP — no public routing.
3. The connection lands on the switch's NLB (:443) → NodePort 30443 on an ingress node → the `istio-ingressgateway` Envoy pod.
4. The Istio `Gateway` terminates TLS in `MUTUAL` mode: it presents the switch's own certificate and validates the DFSP client certificate against the shared CA, at the TLS floor/ciphers above.
5. A `VirtualService` per hostname (account-lookup-service, quoting-service, ml-api-adapter) routes the decrypted request to the matching in-cluster `Service`.
6. Because the destination pod is ambient-enrolled under STRICT `PeerAuthentication`, Istio's automatic mTLS transparently upgrades that last hop too — no explicit `DestinationRule` TLS block is needed; the ingressgateway's Envoy originates mesh mTLS to the SPIFFE-identified destination, terminated by that node's ztunnel.

### Traffic flow — switch → DFSP (outbound)

1. One of the 3 switch deployments that call out to DFSPs (account-lookup-service, quoting-service-handler, the notification handler) makes a plain HTTP call to `http://sim-fspNNN.local/sim/fspNNN/inbound/...`.
2. `sim-fspNNN.local` resolves via a `hostAliases` entry (refreshed from the live DFSP node IPs on every deploy) directly to the target DFSP node — no gateway hop in this direction.
3. The calling pod's own Istio sidecar intercepts that outbound call (interception is scoped to just the DFSP IP ranges, so unrelated pod traffic isn't touched).
4. A `VirtualService` rewrites the path and routes it to port 443 of the DFSP endpoint (declared via a `ServiceEntry`).
5. A `DestinationRule` originates `MUTUAL` TLS using the sidecar's file-mounted client certificate/key/CA (same shared bundle as Leg A), at the same TLS floor/ciphers.
6. On the DFSP side, nginx does a straight SSL passthrough to the scheme-adapter, which terminates the mTLS connection and validates the switch's client certificate.

## 9. Kafka / MySQL performance tuning

**Kafka** (single-broker KRaft, RF=1 everywhere — see §14 for why):
- Listener: SSL-only on port 9092 (client + external); controller/interbroker stay plaintext (never leaves the pod)
- `auto.create.topics.enable=false` — with auto-create on, a client racing ahead of provisioning creates a topic at 1 partition, silently stranding a consumer group sized for N partitions
- Partition counts (validity-gate topics): `topic-transfer-prepare`=12, `topic-transfer-fulfil`=12, `topic-notification-event`=18, `topic-transfer-position-batch`=8, `topic-quotes-post`=12
- `num.network.threads=12`, `num.io.threads=16`, `queued.max.requests=2000`
- `log.segment.bytes=16MB` + `log.segment.ms=60000` + `log.retention.ms=300000` (5min) — retention continuously trims closed segments, keeping broker memory/disk flat (~3-5GB) instead of growing unbounded, which would otherwise trigger an ephemeral-storage eviction
- JVM: G1GC, `MaxGCPauseMillis=20`

**MySQL** (single instance, ephemeral storage — see §14):
- `innodb_buffer_pool_size=8G` (8 instances), `innodb_redo_log_capacity=2G`
- `innodb_flush_log_at_trx_commit=2` + `sync_binlog=0` — relaxed durability for throughput (fsyncs decoupled from per-commit writes); risk/reward visible in the MySQL Overview dashboard's "InnoDB redo log activity" panel
- `innodb_io_capacity=3000` / `_max=6000`, `innodb_doublewrite=0`
- `max_connections=1000`, `thread_cache_size=100`, `table_open_cache=4000`
- `performance_schema=OFF`, `skip_name_resolve=ON`
- Resources: 3 vCPU limit / 2 vCPU request, 12Gi memory limit on an m7i.xlarge (16GiB) node

## 10. Deploy sequence / reproduction

```bash
SLUG=v17.1.0-mtls-mesh-500tps
make terraform-apply SCENARIO=$SLUG    # skip if sharing infra (see §4)
make k8s     SCENARIO=$SLUG
make cilium  SCENARIO=$SLUG
make deploy  SCENARIO=$SLUG
make ambient SCENARIO=$SLUG            # ztunnel + enrollment + STRICT (must run AFTER mtls)
make smoke   SCENARIO=$SLUG
make load    SCENARIO=$SLUG
```

## 11. k6 results (full-run, unclipped)

Full-run e2e p99 963ms (<1s even unclipped), 99.93% success. Raw k6 end-of-run summary:

```
   ✓ checks.........................: 99.97%  ✓ 3628025     ✗ 840
   ✓ completed_transactions.........: 1208804 498.767301/s
     data_received..................: 11 GB   4.4 MB/s
     data_sent......................: 3.4 GB  1.4 MB/s
   ✓ discovery_time.................: avg=22.81ms  min=1ms      med=19ms     max=2.32s   p(90)=32ms     p(95)=39ms     p(99)=62ms
     dropped_iterations.............: 351     0.144827/s
   ✓ e2e_time.......................: avg=642.45ms min=256ms    med=628ms    max=5.82s   p(90)=779ms    p(95)=829ms    p(99)=963ms
     failed_transactions............: 846     0.34907/s
     http_req_blocked...............: avg=3.51µs   min=661ns    med=2.08µs   max=11.65ms p(90)=4.16µs   p(95)=4.83µs   p(99)=9.71µs
     http_req_connecting............: avg=714ns    min=0s       med=0s       max=11.61ms p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=220.68ms min=400.17µs med=154.1ms  max=30.93s  p(90)=500.97ms p(95)=554.11ms p(99)=662.88ms
       { expected_response:true }...: avg=213.91ms min=1.42ms   med=154.05ms max=4.47s   p(90)=500.8ms  p(95)=553.81ms p(99)=661.21ms
     http_req_failed................: 0.02%   ✓ 840         ✗ 3628025
     http_req_receiving.............: avg=26.04µs  min=6.87µs   med=23.73µs  max=5.44ms  p(90)=37.26µs  p(95)=42.32µs  p(99)=54.37µs
     http_req_sending...............: avg=13.71µs  min=3.79µs   med=10.24µs  max=6.52ms  p(90)=15.03µs  p(95)=19.82µs  p(99)=33.09µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=220.64ms min=367.79µs med=154.06ms max=30.93s  p(90)=500.94ms p(95)=554.07ms p(99)=662.84ms
     http_reqs......................: 3628865 1497.314041/s
     iteration_duration.............: avg=662.93ms min=15.53ms  med=628.16ms max=31.74s  p(90)=779.91ms p(95)=829.78ms p(99)=973.29ms
     iterations.....................: 1209650 499.116371/s
   ✓ quote_time.....................: avg=158.81ms min=35ms     med=154ms    max=3.21s   p(90)=230ms    p(95)=252ms    p(99)=297ms
   ✓ success_rate...................: 99.93%  ✓ 1208804     ✗ 846
   ✓ transfer_time..................: avg=460.6ms  min=154ms    med=449ms    max=4.47s   p(90)=579ms    p(95)=622ms    p(99)=742ms
     vus............................: 12      min=0         max=1322
     vus_max........................: 1343    min=1000      max=1343
```

## 12. Steady-state results

| metric | value |
|---|---|
| e2e p50 | 624ms |
| e2e p95 | 823ms |
| **e2e p99** | **910ms** |
| e2e stddev | 109ms |
| transfer p99 | 698ms |
| quote p99 | 288ms |
| discovery p99 | 53ms |
| steady transfers measured | 1,109,349 |
| validity gate | PASS (fulfil/prepare=1.000, notif/prepare=1.999) |

## 13. Capacity used

**Node CPU (steady window):**

| node | avg | peak |
|---|---|---|
| sw1-n1 | 72.4% | 74.0% |
| sw1-n2 | 73.2% | 75.1% |
| sw1-n3 | 83.4% | 85.4% |
| sw1-n4 | 85.4% | 87.7% |
| sw1-n5 | 50.9% | 53.5% |
| kafka | 68.8% | 69.6% |
| mysql | 55.3% | 56.8% |
| monitoring | 21.7% | 23.2% |

**Pod-level CPU/memory by service:** see the Capacity & Saturation dashboard screenshots (§16) — "CPU usage by service" / "Memory (RSS) by service" panels give a direct cross-service comparison.

**Headroom assessment:** hottest node (n4) at 85.4% avg / 87.7% peak — roughly 12-15% headroom to saturation at steady 500 TPS.

## 14. Caveats, concessions, known limitations

- **Kafka RF=1, single broker (KRaft)** — no replication, no HA. Acceptable for a throughput benchmark; not a production posture. A real deployment needs RF≥3.
- **MySQL: single instance, ephemeral storage (`persistence.enabled: false`)** — no HA, no durability across pod restart. `sync_binlog=0` + `innodb_flush_log_at_trx_commit=2` trade a small, quantifiable durability window (up to ~1s of commits) for throughput — see §9's redo-log-activity dashboard panel.
- **auto.create.topics.enable=false** requires the provisioning topic list to cover every topic any deployed consumer subscribes to at boot — a real operational sharp edge if a consumer is added without updating the list.
- **Mongo/Redis mostly disabled** in this profile (no clients in this deployment configuration) — not a statement that Mojoloop doesn't need them in other configurations.

## 15. Other observations / gotchas found

Enabling a TLS-only Kafka listener against the stock charts required the following changes — each is a finding worth reporting, since a stock deployment cannot run Kafka-TLS without them:

- **`wait-for-kafka` init containers replaced with a TCP connect check** (`common/mojaloop/17.1.0.yaml`, all 13 kafka-consuming deployments). The stock check runs a Java Kafka-protocol probe (`kafka-broker-api-versions.sh`) that cannot handshake with a TLS listener — against an SSL-only broker it misreads the TLS handshake as a Kafka frame and dies with `java.lang.OutOfMemoryError`, deadlocking every dependent pod at install. The TCP check preserves the startup-ordering gate and is protocol-agnostic (identical behavior for PLAINTEXT and SSL listeners), so it applies to all scenarios, not just this one. Trade-off: it verifies "listener accepting connections" rather than "broker answering API requests"; the applications' own Kafka clients retry on connect, so the weaker gate is sufficient.
- **Topic-provisioning job rewritten to a truststore-only TLS config** (`provisioning.preScript` in this scenario's `backend.yaml`). The Bitnami chart's provisioning job builds a client keystore from the auto-generated PEM key, which the Java client cannot parse (PKCS#1 vs PKCS#8) — **topic creation fails while the job still exits 0 and reports "Provisioning succeeded"** (silent failure; helm marks the release deployed and deletes the hook). With an encrypt-only listener no client key is needed; the preScript rewrites `client.properties` to truststore-only before the topic commands run.
- **Broker client-auth relaxed to encrypt-only** (`kafka.tls.sslClientAuth: none`). The chart default (`required`) demands client certificates from every Kafka client; the Mojaloop services' rdkafka configuration carries no client certs. Encrypt-only mirrors the MySQL TLS posture (`rejectUnauthorized: false`).
- **TLS keystore/truststore passwords pinned in values** (`kafka.tls.keystorePassword`/`truststorePassword`). Bitnami's upgrade-passwords check otherwise fails every `helm upgrade` once TLS is enabled. Not protective credentials — certificates are auto-generated per install.
- **All rdkafka clients: `security.protocol: ssl` + `enable.ssl.certificate.verification: false`** across 14 service configmaps (~169 producer/consumer blocks) — 7 of them newly added to the configmap patch set because their helm-rendered configs expose no TLS options.
- **Switch deploy ordering** (`ansible/roles/switch`): helm no longer blocks on pod readiness before the configmap patches apply — services cannot become Ready on a TLS-only broker until their patched (SSL) configuration is in place, so waiting first deadlocks the install. Readiness is gated after the patches instead.
- `controller.overrideConfiguration` is a **dead key** in this Kafka chart version (31.5.0) — silently ignored; only `extraConfig` actually applies.

## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/`. Representative panels:

**Capacity & Saturation** — node CPU/mem/PSI + cross-service resource comparison
![Capacity & Saturation](screenshots/Capacity%20&%20Saturation/Capacity%20&%20Saturation%20-%201.png)

**K6 Transaction Latency (client-observed)** — the SLA-gate metric
![K6 e2e latency](<screenshots/K6 Transaction Latency (Client-Observed)/End-to-end transaction latency (p50:p95:p99).png>)

**mTLS / Mesh Overhead** — confirms 100% mutual_tls traffic, sidecar/ztunnel cost
![mTLS Overhead](<screenshots/mTLS : Mesh Overhead/mTLS : Mesh Overhead - 1.png>)

**Kafka - Whitepaper Overview** — validity-gate topic lag/throughput, broker health
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**MySQL Overview** — command breakdown, redo-log activity, buffer pool
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**FSP / DFSP Simulator — Capacity**
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Mojaloop - Central-Ledger - Performance Characterization** — participant cache running at **~99.98% hit rate** (`model_getParticipantsCached-true` ≈4.61K ops/s vs `-false` ≈0.79 ops/s); confirms the §7 replica counts (prepare=12, fulfil=12, service=8) via its "# Pods for each Component" panel.
![Central-Ledger Cache Hits](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

Additional captures (Central Ledger transfer legs, ALS, Quoting Service, ML-API Adapter, Service Mesh Hop Latency) are in their respective `screenshots/` subfolders.
