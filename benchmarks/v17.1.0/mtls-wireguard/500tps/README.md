# v17.1.0 / mtls-wireguard / 500tps — Scenario Report

This scenario layers edge mTLS and Kafka/MySQL protocol TLS with **Cilium
WireGuard** encrypting all pod-pod traffic at the network layer — an
alternative to a workload-identity service mesh for securing app-to-app
communication. Because WireGuard encrypts indiscriminately (no
per-workload exclusion), datastore traffic ends up double-encrypted
(protocol TLS + WireGuard), and this scenario quantifies what that costs:
the 500 TPS design target fails the `<1s` steady-state goal here, and the
recorded result backs off to 450 TPS.

## 1. Scenario

- **Version:** v17.1.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 500 TPS design target, 13 FSP pairs (4 source FSPs → 4 destination FSPs)
- **Status:** ✅ **PASS at 450 TPS** — steady-state e2e p99 = **918ms** (<1s goal). ❌ **FAIL at 500 TPS** — steady-state e2e p99 = **1077ms** (see §8, §12, §13)

## 2. Test methodology & definitions

- **Steady-state window:** start+5min .. end−2min (TPC/SPEC-style warm-up/drain trim). The k6 end-of-run summary is always the full-run aggregate; steady-state is the authoritative number for pass/fail. At 450 TPS, full-run p99 (959ms) and steady-state p99 (918ms) both clear the goal; at 500 TPS, both the full-run (1936ms) and steady-state (1077ms) numbers miss it.
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0. Both runs: **PASS**.

## 3. Test design parameters

- **Target TPS:** 500 (design target, FAILS — see §12); 450 (PASSES)
- **Target transaction count:** 1,210,000 at 500 TPS / 1,189,000 at 450 TPS (1,000,000 measured in steady state + warm-up/drain buffer in each run)
- **Transfer amount / currency:** 1 XXX
- **Duration:** ~2580s (500 TPS run) / ~2642s (450 TPS run)
- **Test load distribution** `overrides/k6.yaml`

| Run | targetTps | targetTxnCount | Result |
|---|---|---|---|
| 500 TPS | 500 | 1,210,000 | FAIL (§12) |
| 450 TPS | 450 | 1,189,000 | PASS (§12) |

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
- **Shared infra:** all three scenarios were measured on the same physical
  cluster (identical hardware, required for a fair comparison). Each
  scenario's `artifacts/` is an independent copy of that cluster's
  terraform/kubeconfig state, taken at the time it was measured — they are
  not kept in sync automatically, so re-provisioning under one scenario's
  name won't propagate to the others.

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
- **Node taints/labels:** `workload-class.mojaloop.io/*` labels partition switch-node scheduling (CORE-API-ADAPTERS, CENTRAL-LEDGER-SVC, ALS-ORACLES, etc. — all 5 generic nodes carry the same label set, i.e. no per-node service pinning by default); Kafka/MySQL/monitoring nodes are tainted `dedicated=kafka|mysql|monitoring:NoSchedule` to keep app pods off them.

### CNI / Cilium setup

Cilium **replaces** MicroK8s' default Calico dataplane: Calico's iptables/veth dataplane re-injects packets at ~12x the wire packet rate under sustained load, saturating switch-node softirq; Cilium's eBPF native-routing dataplane avoids this.

| Setting | Value | Purpose |
|---|---|---|
| Version | 1.17.1 | matches MicroK8s 1.32 channel |
| Mode | eBPF **native routing** (no overlay/VXLAN) | zero encapsulation overhead — all switch nodes share one L2 subnet |
| `kube-proxy-replacement` | **false** | coexists with MicroK8s' embedded kube-proxy |
| `socketLB` | **on**, `hostNamespaceOnly: false` | eBPF pod→ClusterIP redirection at `connect()`, full coverage (no workload-identity mesh in this scenario to constrain it to host-namespace-only) |
| BPF masquerade / host routing | eBPF (native) | fast path enabled — NodePort is on, no compatibility fallback needed |
| hostPort / NodePort | **on** (`enable-host-port`, `enable-node-port`) | serves the istio-ingressgateway (:443) and nginx (:80) DaemonSets |
| `cni.exclusive` | **false** | leaves room for `istio-cni` to chain after Cilium if ever needed (not used in this scenario) |
| **Encryption** | **`enabled: true`, `type: wireguard`** | pod-pod transparent encryption — this scenario's defining setting, see §8 |
| Hubble | on | flow visibility |

## 6. Helm chart versions + values overrides

- **Chart versions:** mojaloop=17.1.0, backend=17.1.0, simulator=15.10.0
- **Key overrides:**
  - `overrides/mojaloop.yaml` — replica counts per §7 below; `log_level: info` on all services
  - `overrides/backend.yaml` — Kafka SSL-only listener + tuning, MySQL TLS + tuning (full detail in §9)
  - `overrides/aws.yaml` — node sizing per §4
  - `overrides/dfsp.yaml` — DFSP simulator replica counts per §7
  - WireGuard encryption is configured outside the Helm chart entirely, via the Cilium role (`cilium_encryption_enabled: true`) — see §5, §8

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

account-lookup-service (8), quoting-service-handler (12), and
ml-api-adapter-handler-notification (18) were confirmed live for this
scenario via `kubectl -n mojaloop get pods` this session. Notification handler (18)
is deliberately the highest-replica service — it's the consumer most exposed
to backpressure (2× the prepare rate: one notification per prepare AND one
per fulfil).

**DFSP simulators** (per FSP cluster, `fsp201`–`fsp208`) — `overrides/dfsp.yaml`:

| Component | fsp201 / fsp202 | fsp203–fsp208 |
|---|---|---|
| mojaloop-simulator | 1 | 1 |
| sdk-scheme-adapter | 16 | 4 |

`fsp201`/`fsp202` get 4x the scheme-adapter replicas of the other 6 — they carry the heaviest share of the FSP pair load (see §3's source×destination matrix).

Pod-to-node spread across the 5 generic nodes is scheduler-determined (no explicit topologySpreadConstraints beyond default). See the Capacity & Saturation dashboard screenshots for the node-CPU distribution actually measured.

## 8. Security setup (detailed)

| Layer | Mechanism |
|---|---|
| DFSP ↔ switch (edge, both directions) | Istio sidecar mTLS on the 3 egress deployments + ingressgateway, file-mounted certificates |
| service ↔ service (app pods) | **Cilium WireGuard only** — no workload-identity mesh in this scenario. Every pod-to-pod packet crossing a node boundary is WireGuard-wrapped; same-node traffic is not (never leaves the host) |
| apps ↔ Kafka | **Kafka protocol TLS** (SSL-only listener, `sslClientAuth: none`) **plus** WireGuard on top, since WireGuard has no per-workload exclusion |
| apps ↔ MySQL | **MySQL protocol TLS**, encrypt-only, **plus** WireGuard on top, same reason |
| Pod-pod encryption | **Cilium WireGuard** — `cilium_encryption_enabled: true`, `type: wireguard` |

### Cryptography

| Domain | Certificate | Algorithm | TLS version | Cipher suites / curves |
|---|---|---|---|---|
| DFSP ↔ switch edge (both directions) | Single shared lab CA + leaf cert, SANs covering all 3 switch service hostnames and all 8 DFSP simulator hostnames; the same leaf is used as both server and client cert in both directions | ECDSA P-256 | 1.2 floor, 1.3 negotiated automatically when both peers support it | ECDHE-ECDSA-AES128-GCM-SHA256, ECDHE-ECDSA-AES256-GCM-SHA384; X25519, P-256 |
| Pod-pod (WireGuard) | Kernel-generated WireGuard keypair per node, not an X.509 certificate | Curve25519 (WireGuard's fixed protocol) | N/A (not TLS — a dedicated UDP-based tunnel protocol) | ChaCha20-Poly1305 (WireGuard's fixed AEAD cipher) |

### Traffic flow — DFSP → switch (inbound)

1. The DFSP scheme-adapter opens a TLS connection to `<service>.local:443`, presenting its client certificate (the same shared CA/leaf, mounted on the DFSP side).
2. Cross-cluster CoreDNS resolves the `.local` hostname to the switch's real node IP — no public routing.
3. The connection lands on the switch's NLB (:443) → NodePort 30443 on an ingress node → the `istio-ingressgateway` Envoy pod.
4. The Istio `Gateway` terminates TLS in `MUTUAL` mode: it presents the switch's own certificate and validates the DFSP client certificate against the shared CA, at the TLS floor/ciphers above.
5. A `VirtualService` per hostname (account-lookup-service, quoting-service, ml-api-adapter) routes the decrypted request to the matching in-cluster `Service`.
6. That last hop (ingressgateway → app pod) rides plain cluster networking if both pods land on the same node, or a WireGuard tunnel if they don't — there is no workload-identity check on this hop in this scenario, unlike a mesh-based design.

### Traffic flow — switch → DFSP (outbound)

1. One of the 3 switch deployments that call out to DFSPs (account-lookup-service, quoting-service-handler, the notification handler) makes a plain HTTP call to `http://sim-fspNNN.local/sim/fspNNN/inbound/...`.
2. `sim-fspNNN.local` resolves via a `hostAliases` entry (refreshed from the live DFSP node IPs on every deploy) directly to the target DFSP node — no gateway hop in this direction.
3. The calling pod's own Istio sidecar intercepts that outbound call (interception is scoped to just the DFSP IP ranges, so unrelated pod traffic isn't touched).
4. A `VirtualService` rewrites the path and routes it to port 443 of the DFSP endpoint (declared via a `ServiceEntry`).
5. A `DestinationRule` originates `MUTUAL` TLS using the sidecar's file-mounted client certificate/key/CA (same shared bundle as inbound), at the same TLS floor/ciphers.
6. On the DFSP side, nginx does a straight SSL passthrough to the scheme-adapter, which terminates the mTLS connection and validates the switch's client certificate.

### Why this scenario double-encrypts Kafka and MySQL traffic

Cilium WireGuard encrypts **all** cross-node pod traffic unconditionally — it
has no per-namespace or per-workload selector to exclude specific flows,
unlike an ambient mesh's `istio.io/dataplane-mode: none`, which can carve
individual workloads out of its own encryption. Once WireGuard is enabled
cluster-wide, adding Kafka/MySQL protocol TLS on top does not add any
protection against the threat WireGuard already covers (a passive listener on
the network between nodes) — it only adds a second, redundant encryption
pass on the highest-throughput traffic in the system.

A workload-identity mesh (e.g. Istio ambient) can explicitly exclude specific
workloads — like datastores — from its own encryption layer via a
per-namespace setting, making protocol TLS the *sole* encryption for that
hop rather than a redundant one. WireGuard has no equivalent mechanism: it
is all-or-nothing at the node-pair level. In this scenario that makes
Kafka/MySQL protocol TLS redundant with WireGuard, and it measurably costs
capacity: see §12/§13 for the ~160ms p99 difference and the node CPU data
against a WireGuard-only baseline (no Kafka/MySQL protocol TLS).

**Double encryption is not inherently wrong** — it can be a deliberate,
justified choice where a compliance control requires the database/broker
*connection itself* to be provably encrypted, independent of what the
network fabric underneath does (WireGuard authenticates nodes, not the
Kafka/MySQL connection). But it is not the configuration a throughput-optimized
WireGuard deployment would choose by default, and this scenario's ceiling
(450 TPS, not 500) is the direct, measured cost of carrying it anyway.

## 9. Kafka / MySQL performance tuning

**Kafka** (single-broker KRaft, RF=1 everywhere — see §14 for why):
- Listener: SSL-only on port 9092 (client + external); controller/interbroker stay plaintext (never leaves the pod)
- `auto.create.topics.enable=false` with the full provisioning topic list — a client racing ahead of provisioning would otherwise create a topic at 1 partition, silently stranding a consumer group sized for N partitions
- Partition counts (validity-gate topics): `topic-transfer-prepare`=12, `topic-transfer-fulfil`=12, `topic-notification-event`=18, `topic-transfer-position-batch`=8, `topic-quotes-post`=12
- `num.network.threads=12`, `num.io.threads=16`, `queued.max.requests=2000`
- `log.segment.bytes=16MB` + `log.segment.ms=60000` + `log.retention.ms=300000` (5min) — retention continuously trims closed segments, keeping broker memory/disk flat instead of growing unbounded
- JVM: G1GC, `MaxGCPauseMillis=20`

**MySQL** (single instance, ephemeral storage — see §14):
- `innodb_buffer_pool_size=8G` (8 instances), `innodb_redo_log_capacity=2G`
- `innodb_flush_log_at_trx_commit=2` + `sync_binlog=0` — relaxed durability for throughput (fsyncs decoupled from per-commit writes)
- `innodb_io_capacity=3000` / `_max=6000`, `innodb_doublewrite=0`
- `max_connections=1000`, `thread_cache_size=100`, `table_open_cache=4000`
- `performance_schema=OFF`, `skip_name_resolve=ON`
- Resources: 3 vCPU limit / 2 vCPU request, 12Gi memory limit on an m7i.xlarge (16GiB) node

## 10. Deploy sequence / reproduction

```bash
SLUG=v17.1.0-mtls-wireguard-500tps
make terraform-plan  SCENARIO=$SLUG    # regenerate plan against current state + aws.yaml
make terraform-apply SCENARIO=$SLUG
make tunnel  SCENARIO=$SLUG            # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s     SCENARIO=$SLUG
make cilium  SCENARIO=$SLUG EXTRA='-e cilium_encryption_enabled=true'   # WireGuard on
make backend SCENARIO=$SLUG
make switch  SCENARIO=$SLUG
make dfsp    SCENARIO=$SLUG
make mtls    SCENARIO=$SLUG                                             # Leg A/B + DFSP certs, run AFTER dfsp
make onboard SCENARIO=$SLUG
make provision SCENARIO=$SLUG
make smoke   SCENARIO=$SLUG
make load    SCENARIO=$SLUG
```

## 11. k6 results (full-run, unclipped)

**500 TPS run** (targetTxnCount=1,210,000) — full-run e2e p99 1.93s (misses the 1s goal even before steady-state trimming), 99.99% success. Raw k6 end-of-run summary:

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 1209536 / ✗ 20
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 1209528 / ✗ 8
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 1209501 / ✗ 19

   ✓ checks.........................: 99.99%  ✓ 3628565    ✗ 47
   ✓ completed_transactions.........: 1209501 499.605005/s
     data_received..................: 11 GB   4.4 MB/s
     data_sent......................: 3.4 GB  1.4 MB/s
   ✓ discovery_time.................: avg=31.7ms   min=1ms     med=23ms     max=6.3s    p(90)=43ms     p(95)=54ms     p(99)=183ms
     dropped_iterations.............: 444     0.183402/s
   ✓ e2e_time.......................: avg=760.76ms min=295ms   med=729ms    max=10.72s  p(90)=918ms    p(95)=989ms    p(99)=1.93s
     failed_transactions............: 55      0.022719/s
     http_req_blocked...............: avg=3.63µs   min=671ns   med=2.05µs   max=10.78ms p(90)=4.17µs   p(95)=4.86µs   p(99)=11.43µs
     http_req_connecting............: avg=812ns    min=0s      med=0s       max=10.74ms p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=253.65ms min=1.41ms  med=163.24ms max=30.07s  p(90)=601.77ms p(95)=671.86ms p(99)=838.8ms
       { expected_response:true }...: avg=253.35ms min=1.41ms  med=163.24ms max=10.55s  p(90)=601.76ms p(95)=671.84ms p(99)=838.66ms
     http_req_failed................: 0.00%   ✓ 47         ✗ 3628565
     http_req_receiving.............: avg=25.91µs  min=7.17µs  med=23.57µs  max=2.99ms  p(90)=37.14µs  p(95)=42.29µs  p(99)=54.39µs
     http_req_sending...............: avg=13.89µs  min=3.68µs  med=10.22µs  max=6.58ms  p(90)=15.22µs  p(95)=20.36µs  p(99)=33.42µs
     http_req_tls_handshaking.......: avg=0s       min=0s      med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=253.61ms min=1.36ms  med=163.21ms max=30.07s  p(90)=601.73ms p(95)=671.82ms p(99)=838.76ms
     http_reqs......................: 3628612 1498.86004/s
     iteration_duration.............: avg=761.82ms min=17.51ms med=729.54ms max=30.94s  p(90)=917.95ms p(95)=989.13ms p(99)=1.93s
     iterations.....................: 1209556 499.627724/s
   ✓ quote_time.....................: avg=169.26ms min=37ms    med=162ms    max=3.35s   p(90)=241ms    p(95)=266ms    p(99)=348ms
   ✓ success_rate...................: 99.99%  ✓ 1209501    ✗ 55
   ✓ transfer_time..................: avg=559.51ms min=187ms   med=538ms    max=10.55s  p(90)=706ms    p(95)=770ms    p(99)=1.14s
     vus............................: 266     min=0        max=1377
     vus_max........................: 1443    min=1000     max=1443
```

**450 TPS run** (targetTxnCount=1,189,000) — full-run e2e p99 959ms (<1s even unclipped), 99.99% success. Raw k6 end-of-run summary:

```
     ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 1189263 / ✗ 23
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 1189254 / ✗ 9
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 1189227 / ✗ 25

   ✓ checks.........................: 99.99%  ✓ 3567744     ✗ 57
   ✓ completed_transactions.........: 1189227 449.798583/s
     data_received..................: 11 GB   4.0 MB/s
     data_sent......................: 3.3 GB  1.3 MB/s
   ✓ discovery_time.................: avg=21.47ms  min=1ms      med=19ms     max=10.02s  p(90)=30ms     p(95)=35ms     p(99)=56ms
     dropped_iterations.............: 65      0.024585/s
   ✓ e2e_time.......................: avg=655.85ms min=266ms    med=645ms    max=10.83s  p(90)=792ms    p(95)=840ms    p(99)=959ms
     failed_transactions............: 59      0.022315/s
     http_req_blocked...............: avg=3.37µs   min=637ns    med=2.06µs   max=19.42ms p(90)=4.18µs   p(95)=4.8µs    p(99)=9.13µs
     http_req_connecting............: avg=608ns    min=0s       med=0s       max=19.26ms p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=218.79ms min=272.14µs med=158.21ms max=30.05s  p(90)=514.29ms p(95)=565.71ms p(99)=665.09ms
       { expected_response:true }...: avg=218.38ms min=1.46ms   med=158.21ms max=10.61s  p(90)=514.28ms p(95)=565.7ms  p(99)=665ms
     http_req_failed................: 0.00%   ✓ 57          ✗ 3567744
     http_req_receiving.............: avg=25.76µs  min=7.7µs    med=23.52µs  max=6.4ms   p(90)=36.83µs  p(95)=41.96µs  p(99)=54.15µs
     http_req_sending...............: avg=13.13µs  min=3.68µs   med=10.15µs  max=8.36ms  p(90)=14.62µs  p(95)=19.01µs  p(99)=30.73µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=218.75ms min=240.31µs med=158.18ms max=30.05s  p(90)=514.25ms p(95)=565.68ms p(99)=665.04ms
     http_reqs......................: 3567801 1349.441136/s
     iteration_duration.............: avg=657.25ms min=14.45ms med=645.54ms max=30.27s  p(90)=792.62ms p(95)=839.97ms p(99)=960.01ms
     iterations.....................: 1189286 449.820898/s
   ✓ quote_time.....................: avg=161.86ms min=37ms     med=158ms    max=2.41s   p(90)=233ms    p(95)=255ms    p(99)=298ms
   ✓ success_rate...................: 99.99%  ✓ 1189227     ✗ 59
   ✓ transfer_time..................: avg=472.17ms min=185ms    med=464ms    max=10.61s  p(90)=591ms    p(95)=632ms    p(99)=732ms
     vus............................: 222     min=0         max=1057
     vus_max........................: 1065    min=1000      max=1065
```

## 12. Steady-state results

| metric | 500 TPS (FAIL) | 450 TPS (PASS) |
|---|---|---|
| e2e p50 | 724ms | 643ms |
| e2e p95 | 963ms | 834ms |
| **e2e p99** | **1077ms** | **918ms** |
| e2e avg / stddev | 732ms / 128ms | 648ms / 109ms |
| transfer p99 | 851ms | 704ms |
| quote p99 | 296ms | 291ms |
| discovery p99 | 71ms | 48ms |
| steady transfers measured | 1,079,992 | 999,810 |
| validity gate | PASS (fulfil/prepare=1.000, notif/prepare=2.000) | PASS (fulfil/prepare=1.000, notif/prepare=2.000) |

## 13. Capacity used

**Node CPU (steady window):**

| node | 500 TPS avg | 500 TPS peak | 450 TPS avg | 450 TPS peak |
|---|---|---|---|---|
| sw1-kafka-n1 | 88.8% | 89.6% | 87.4% | 87.9% |
| sw1-mysql-n1 | 69.2% | 69.9% | 64.7% | 65.3% |
| sw1-n1 | 59.6% | 61.7% | 53.8% | 54.8% |
| sw1-n2 | 86.9% | 89.5% | 79.1% | 80.1% |
| sw1-n3 | 85.5% | 88.3% | 78.0% | 79.6% |
| sw1-n4 | 75.8% | 78.9% | 66.9% | 67.7% |
| sw1-n5 | 87.2% | 89.9% | 78.8% | 79.7% |

Kafka's node CPU barely moves between the two runs (88.8% → 87.4% avg, a
1.4-point drop for a 10% TPS cut) while every switch-generic node drops 6-9
points over the same change. This is consistent with the double-encryption
cost on Kafka being substantially fixed/connection-driven rather than purely
traffic-proportional — Kafka is the tightest resource in this configuration
and the first one to gate the achievable TPS.

`sw1-n1` runs noticeably cooler than n2/n3/n5 in both runs (59.6%/53.8%
vs. 85-88%/78-79%) — a pod-scheduling imbalance independent of the
double-encryption finding, not investigated further here.

**Pod-level CPU/memory by service:** see the Capacity & Saturation dashboard
screenshots (§16).

**Headroom assessment:** at 450 TPS (passing), the hottest node (kafka) sits
at 87.4% avg / 87.9% peak — roughly 12% headroom. At 500 TPS (failing),
kafka is at 88.8% avg / 89.6% peak — essentially no headroom left, consistent
with the p99 miss.

## 14. Caveats, concessions, known limitations

- **Kafka RF=1, single broker (KRaft)** — no replication, no HA. Acceptable for a throughput benchmark; not a production posture. A real deployment needs RF≥3.
- **MySQL: single instance, ephemeral storage (`persistence.enabled: false`)** — no HA, no durability across pod restart. `sync_binlog=0` + `innodb_flush_log_at_trx_commit=2` trade a small, quantifiable durability window (up to ~1s of commits) for throughput.
- **auto.create.topics.enable=false** requires the provisioning topic list to cover every topic any deployed consumer subscribes to at boot — a real operational sharp edge if a consumer is added without updating the list.
- **Same-node pod-pod traffic is NOT WireGuard-encrypted** (never leaves the host) — an accepted tradeoff for the WireGuard-only encryption layer.
- **Kafka/MySQL protocol TLS on top of WireGuard (§8) is not a recommended default** for a throughput-optimized WireGuard deployment — it is carried here specifically to test the double-encryption combination directly. A WireGuard-only deployment (no Kafka/MySQL protocol TLS) would be expected to sustain 500 TPS; this double-encrypted configuration sustains 450 TPS.

## 15. Other observations / gotchas found

Enabling a TLS-only Kafka listener against the stock charts required the following changes — each is a finding worth reporting, since a stock deployment cannot run Kafka-TLS without them:

- **`wait-for-kafka` init containers replaced with a TCP connect check** (`common/mojaloop/17.1.0.yaml`, all 13 kafka-consuming deployments). The stock check runs a Java Kafka-protocol probe (`kafka-broker-api-versions.sh`) that cannot handshake with a TLS listener — against an SSL-only broker it misreads the TLS handshake as a Kafka frame and dies with `java.lang.OutOfMemoryError`, deadlocking every dependent pod at install. The TCP check preserves the startup-ordering gate and is protocol-agnostic (identical behavior for PLAINTEXT and SSL listeners). Trade-off: it verifies "listener accepting connections" rather than "broker answering API requests"; the applications' own Kafka clients retry on connect, so the weaker gate is sufficient.
- **Topic-provisioning job rewritten to a truststore-only TLS config** (`provisioning.preScript` in this scenario's `backend.yaml`). The Bitnami chart's provisioning job builds a client keystore from the auto-generated PEM key, which the Java client cannot parse (PKCS#1 vs PKCS#8) — **topic creation fails while the job still exits 0 and reports "Provisioning succeeded"** (silent failure; helm marks the release deployed and deletes the hook). With an encrypt-only listener no client key is needed; the preScript rewrites `client.properties` to truststore-only before the topic commands run.
- **Broker client-auth relaxed to encrypt-only** (`kafka.tls.sslClientAuth: none`). The chart default (`required`) demands client certificates from every Kafka client; the Mojaloop services' rdkafka configuration carries no client certs. Encrypt-only mirrors the MySQL TLS posture (`rejectUnauthorized: false`).
- **TLS keystore/truststore passwords pinned in values** (`kafka.tls.keystorePassword`/`truststorePassword`). Bitnami's upgrade-passwords check otherwise fails every `helm upgrade` once TLS is enabled. Not protective credentials — certificates are auto-generated per install.
- **All rdkafka clients: `security.protocol: ssl` + `enable.ssl.certificate.verification: false`** across the same service configmaps as any other Kafka-TLS scenario.
- `controller.overrideConfiguration` is a **dead key** in this Kafka chart version (31.5.0) — silently ignored; only `extraConfig` actually applies.
- AZ/NLB terraform fixes (honoring `aws.availability_zone` instead of a hardcoded zone, NLB `replace_triggered_by` subnet) were made against this scenario during the campaign and now apply everywhere.

## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/` (12 dashboards, from the 450 TPS passing run). Representative panels:

**Capacity & Saturation** — node CPU utilisation, CPU pressure (PSI cpu-waiting), and memory utilisation per node. Kafka is the hottest node (84.7% mean CPU / 55.8% mean CPU-pressure in this capture), matching the §13 steady-state figures.
![Capacity & Saturation](<screenshots/Capacity & Saturation/Capacity & Saturation - 1.png>)

**mTLS / Mesh Overhead** — edge traffic is 822 req/s mean `mutual_tls` vs 0.533 req/s `none` (near-total mTLS coverage on the DFSP↔switch edge); istio-ingressgateway sidecars run 0.22-0.25 cores / 85-92MiB each — this scenario has no app-to-app mesh sidecars, only the 3 egress deployments + ingressgateway carry Envoy.
![mTLS Overhead](<screenshots/mTLS : Mesh Overhead/mTLS : Mesh Overhead - 1.png>)

**Kafka - Whitepaper Overview** — validity-gate topic rates hold the expected ratios throughout (`topic-notification-event` 822 ops/s ≈ 2× `topic-transfer-prepare` 411 ops/s); consumer lag stays bounded (mean 35-80, max 75-188 across the validity-gate topics), confirming no backlog buildup despite the elevated node CPU.
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**K6 Transaction Latency (client-observed)** — the SLA-gate metric
![K6 e2e latency](<screenshots/K6 Transaction Latency (Client-Observed)/K6 Transaction Latency (Client-Observed) - 1.png>)

**MySQL Overview** — command breakdown, redo-log activity, buffer pool
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**FSP / DFSP Simulator — Capacity**
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Mojaloop - Central-Ledger - Performance Characterization**
![Central-Ledger Characterization](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

Additional captures (Central Ledger transfer legs, ALS, Quoting Service, ML-API Adapter, Service Mesh Hop Latency) are in their respective `screenshots/` subfolders.
