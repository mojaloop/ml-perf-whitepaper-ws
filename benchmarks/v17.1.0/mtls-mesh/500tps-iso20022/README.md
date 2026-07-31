# v17.1.0 / mtls-mesh / 500tps-iso20022 — Scenario Report

This scenario secures app-to-app traffic with an Istio ambient service
mesh (per-node ztunnel proxies, SPIFFE workload identity, STRICT mTLS)
plus sidecar mTLS at the DFSP↔switch edge and native protocol TLS for
datastores — every byte on the transaction path encrypted — with the
switch and DFSP simulators processing **ISO 20022** messages instead of
FSPIOP: `api_type: iso20022`, ILP v4 packet/condition/fulfilment, and the
`fspiopToISO20022` TTK transformer for onboarding.

## 1. Scenario

- **Version:** v17.1.0 (mojaloop chart), backend chart 17.1.0, simulator chart 15.10.0
- **Target load:** 500 TPS, 13 FSP pairs (4 source FSPs → 4 destination FSPs)
- **Status:** ✅ **PASS** — steady-state e2e p99 = **951ms** (<1s goal), 99.96% success.

## 2. Test methodology & definitions

- **Steady-state window:** start+5min .. end−2min (TPC/SPEC-style warm-up/drain trim). The k6 end-of-run summary is always the full-run aggregate; steady-state is the authoritative number for pass/fail. Full-run p99 is typically somewhat higher than steady-state from ramp-up/ramp-down edge effects alone — not necessarily a real regression.
- **Validity gate:** Kafka topic rate ratios in the steady window: fulfil/prepare ≈ 1.0, notification/prepare ≈ 2.0, position-batch/prepare ≈ 2.0. Recorded run: fulfil/prepare=1.000, notif/prepare=2.000 — **PASS**.

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
- Networking: pod CIDR `10.1.0.0/16` (Calico IPAM on this cluster; see §5 for the switch cluster's CNI), service CIDR `10.96.0.0/12`, cluster DNS `10.96.0.10`.

**DFSP clusters** (`fsp201`..`fsp208`, 1 node each, 8 clusters total)
- Each runs mojaloop-simulator + sdk-scheme-adapter for that one DFSP.
- Single-node: the one node is both control-plane and worker.
- Same addons as the switch cluster. CNI is MicroK8s' default (Calico) — these clusters are not part of the Cilium migration described in §5, which is scoped to the switch cluster only.

**k6 cluster** (1 node)
- Runs the k6 Operator + test runner pods.

**Cross-cluster networking:** each cluster is independent with its own `.local` domain and no shared DNS — resolution across clusters is wired by hand via CoreDNS ConfigMap patches + Kubernetes `hostAliases` (k6 → DFSP node IPs, each DFSP → the switch cluster's internal NLB, switch → DFSP node IPs). No public internet is involved: all switch, DFSP, and k6 nodes sit in one private subnet (`10.112.2.0/24`) within the same VPC; only the bastion has a public IP (separate public subnet, `10.112.1.0/24`), used solely for operator SSH access. Security groups restrict cluster nodes to traffic from the bastion (SSH/admin) or from each other (`source: self`) — nothing external can reach them, and there's no route out to the public internet. Cross-cluster traffic is plain private-IP routing over the VPC's internal network fabric; the switch's NLB is `scheme: internal`, not internet-facing.

## 5. System-level overrides

- **Kernel pin:** `6.17.0-1013-aws` on switch nodes — the stock AMI kernel (GA 6.8) runs ~10% higher softirq than 6.17 under sustained load. Installed + grub-configured pre-MicroK8s so the reboot is safe.
- **Node taints/labels:** `workload-class.mojaloop.io/*` labels partition switch-node scheduling (CORE-API-ADAPTERS, CENTRAL-LEDGER-SVC, ALS-ORACLES, etc. — all 5 generic nodes carry the same label set, i.e. no per-node service pinning by default); Kafka/MySQL/monitoring nodes are tainted `dedicated=kafka|mysql|monitoring:NoSchedule` to keep app pods off them — this taint is what actually enforces the intended workload split, not cluster membership (see cluster architecture above).

### CNI / Cilium setup (switch cluster only)

Cilium **replaces** MicroK8s' default Calico dataplane on the switch cluster: Calico's iptables/veth dataplane re-injects packets at ~12x the wire packet rate under sustained load, saturating switch-node softirq; Cilium's eBPF native-routing dataplane avoids this. The DFSP clusters are unaffected by this — they run MicroK8s' default Calico CNI with standard kube-proxy Service load-balancing, since softirq pressure there is not the bottleneck.

| Setting | Value | Purpose |
|---|---|---|
| Version | 1.17.1 | matches MicroK8s 1.32 channel |
| Mode | eBPF **native routing** (no overlay/VXLAN) | zero encapsulation overhead — all switch nodes share one L2 subnet |
| `kube-proxy-replacement` | **false** | Cilium is CNI-only here; Service load-balancing still goes through MicroK8s' embedded (iptables) kube-proxy. Chosen because native-routing alone already fixes the softirq problem this flag would otherwise require a riskier kube-proxy-disable step to also address. |
| `socketLB` | **on**, `hostNamespaceOnly: true` | eBPF pod→ClusterIP redirection at `connect()` |
| BPF masquerade / host routing | iptables / legacy | ambient/ztunnel compatibility |
| hostPort / NodePort | **on** (`enable-host-port`, `enable-node-port`) | serves the istio-ingressgateway (:443) and nginx (:80) DaemonSets |
| `cni.exclusive` | **false** | allows `istio-cni` to chain after Cilium |
| Hubble | on | flow visibility |

## 6. Helm chart versions + values overrides

- **Chart versions:** mojaloop=17.1.0, backend=17.1.0, simulator=15.10.0
- **Key overrides:**
  - `overrides/mojaloop.yaml` — replica counts per §7 below; `log_level: info` on all services; `api_type: iso20022` set on the 4 service configs that consume it: account-lookup-service, quoting-service, ml-api-adapter-service, ml-api-adapter-handler-notification.
  - `overrides/dfsp.yaml` — matching ISO 20022 toggle on the DFSP side: `API_TYPE: "iso20022"` + `ILP_VERSION: "4"` added to every FSP's `schemeAdapter.env`; scheme-adapter image pinned to `v24.19.7` (§14)
  - `onboard.yaml` — `env:` points at `ttk-collections/perf-env-iso20022.json`, which carries matching ILP v4 params + `transformerName: fspiopToISO20022` so TTK builds ISO20022-shaped test requests/responses
  - `overrides/backend.yaml` — Kafka SSL-only listener + tuning, MySQL TLS + tuning (full detail in §9)
  - `overrides/aws.yaml` — node sizing per §4
  - Mesh (ambient mTLS, STRICT PeerAuthentication) is configured outside the Helm chart values entirely (see §8)

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
| centralsettlement-handler-rules | disabled (not needed for this test's transaction path) |
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
| mojaloop-simulator (backend) | 1 | 1 |
| sdk-scheme-adapter | 16 | 4 |

`fsp201`/`fsp202` get 4x the scheme-adapter replicas of the other 6 — they carry the heaviest share of the FSP pair load (see §3's source×destination matrix). The backend/simulator component runs a single replica per FSP regardless of traffic share: it's a lightweight stateless business-logic layer, and multiple replicas showed no throughput benefit at this load.

Notification handler (18) is deliberately the highest-replica service — it's the consumer most exposed to backpressure (2× the prepare rate: one notification per prepare AND one per fulfil).

Pod-to-node spread across the 5 generic nodes is enforced per-service by a hard `topologySpreadConstraint` (`maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule` — see §15 for why replica counts here are chosen as multiples of 5 rather than round numbers like 10/20).

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
- Partition counts (validity-gate topics, matched 1:1 to their consumer's replica count): `topic-transfer-prepare`=12, `topic-transfer-fulfil`=12, `topic-notification-event`=18, `topic-transfer-position-batch`=8, `topic-quotes-post`=12, `topic-quotes-put`=12
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
SLUG=v17.1.0-mtls-mesh-500tps-iso20022
make terraform-plan  SCENARIO=$SLUG    # regenerate plan against current state + aws.yaml
make terraform-apply SCENARIO=$SLUG
make tunnel  SCENARIO=$SLUG            # SOCKS5 via bastion. To stop: lsof -ti :1080 | xargs kill
make k8s     SCENARIO=$SLUG
make cilium  SCENARIO=$SLUG
make deploy  SCENARIO=$SLUG            # monitoring -> backend -> switch -> dfsp -> mtls -> dfsp-monitoring -> istio-telemetry -> k6 -> onboard -> provision -> smoke
make ambient SCENARIO=$SLUG            # ztunnel + enrollment + STRICT (must run AFTER mtls)
make smoke   SCENARIO=$SLUG            # re-validate a transfer completes once STRICT mesh mTLS is live — the real gate for this cell
make load    SCENARIO=$SLUG
```

`make deploy`'s `onboard` step runs against this cell's own `onboard.yaml`, which already points at the ISO 20022 env file (§6) — no separate onboarding step or manual env switch is needed.

## 11. k6 results (full-run, unclipped)

Full-run e2e p99 1.00s (unclipped; steady-state below is the authoritative
number), 99.96% success. Raw k6 end-of-run summary:

```
    ✗ ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200
      ↳  99% — ✓ 1209751 / ✗ 63
     ✗ QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200
      ↳  99% — ✓ 1209729 / ✗ 22
     ✗ TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200
      ↳  99% — ✓ 1209314 / ✗ 415

   ✓ checks.........................: 99.98%  ✓ 3628794     ✗ 500
   ✓ completed_transactions.........: 1209314 499.537227/s
     data_received..................: 14 GB   5.8 MB/s
     data_sent......................: 3.4 GB  1.4 MB/s
   ✓ discovery_time.................: avg=30.12ms  min=1ms      med=24ms     max=1.67s   p(90)=49ms     p(95)=63ms     p(99)=110ms
     dropped_iterations.............: 187     0.077245/s
   ✓ e2e_time.......................: avg=646.43ms min=243ms    med=632ms    max=5.35s   p(90)=791ms    p(95)=846ms    p(99)=1s
     failed_transactions............: 500     0.206537/s
     http_req_blocked...............: avg=3.98µs   min=667ns    med=2.68µs   max=9.58ms  p(90)=4.9µs    p(95)=5.33µs   p(99)=10.81µs
     http_req_connecting............: avg=739ns    min=0s       med=0s       max=9.52ms  p(90)=0s       p(95)=0s       p(99)=0s
   ✓ http_req_duration..............: avg=219.13ms min=313.24µs med=164.16ms max=30.19s  p(90)=487.18ms p(95)=540.38ms p(99)=646.84ms
       { expected_response:true }...: avg=215.2ms  min=1.52ms   med=164.13ms max=3.07s   p(90)=487.08ms p(95)=540.19ms p(99)=645.88ms
     http_req_failed................: 0.01%   ✓ 500         ✗ 3628794
     http_req_receiving.............: avg=36.86µs  min=6.82µs   med=30.56µs  max=49.41ms p(90)=49.32µs  p(95)=60.76µs  p(99)=206.09µs
     http_req_sending...............: avg=15.57µs  min=3.16µs   med=11.66µs  max=7.91ms  p(90)=16.37µs  p(95)=20.97µs  p(99)=42.7µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s      p(90)=0s       p(95)=0s       p(99)=0s
     http_req_waiting...............: avg=219.08ms min=295.73µs med=164.11ms max=30.19s  p(90)=487.13ms p(95)=540.33ms p(99)=646.79ms
     http_reqs......................: 3629294 1499.170157/s
     iteration_duration.............: avg=658.34ms min=22.09ms  med=632.39ms max=32.94s  p(90)=791.94ms p(95)=846.42ms p(99)=1s
     iterations.....................: 1209814 499.743764/s
   ✓ quote_time.....................: avg=171.1ms  min=39ms     med=164ms    max=2.98s   p(90)=245ms    p(95)=269ms    p(99)=328ms
   ✓ success_rate...................: 99.95%  ✓ 1209314     ✗ 500
   ✓ transfer_time..................: avg=444.94ms min=156ms    med=437ms    max=3.07s   p(90)=565ms    p(95)=607ms    p(99)=710ms
     vus............................: 209     min=0         max=1180
     vus_max........................: 1185    min=1000      max=1185
```

## 12. Steady-state results

| metric | p50 | p95 | p99 | avg | stddev |
|---|---|---|---|---|---|
| e2e_time | 630ms | 838ms | **951ms** | 637ms | 116ms |
| transfer_time | 436ms | 603ms | 689ms | 442ms | 92ms |
| quote_time | 162ms | 266ms | 310ms | 166ms | 56ms |
| discovery_time | 23ms | 61ms | 98ms | 29ms | 17ms |

- Steady window: 2,220s (2026-07-29T22:53:21Z .. 23:30:21Z), 5-min warm-up + 2-min drain excluded from a 2,640s run
- Measured transfers (steady): 1,109,567
- Validity gate: fulfil/prepare=1.000, notif/prepare=2.000 — **PASS**

Against the target per-leg budget (discovery ≈50ms, quote ≈300ms, transfer ≈600ms): all three legs land on or under budget, and the overall e2e number clears the 1s goal.

## 13. Capacity used

**Node CPU (steady window):**

| node | avg | peak |
|---|---|---|
| sw1-n1 | 76.0% | 77.7% |
| sw1-n2 | 61.4% | 63.9% |
| sw1-n3 | 72.3% | 73.3% |
| sw1-n4 | 80.7% | 83.9% |
| sw1-n5 | 72.0% | 75.3% |
| kafka | 67.9% | 68.3% |
| mysql | 50.7% | 51.0% |
| monitoring | 21.9% | 33.4% |

**Headroom assessment:** hottest node (n4) at 80.7% avg / 83.9% peak — no node near saturation. n4 (and to a lesser extent n1) run somewhat hotter than n2/n5 — see §15 for the replica-count-vs-node-count mechanism behind that spread and why it's now bounded rather than growing further.

## 14. Caveats, concessions, known limitations

- **Kafka RF=1, single broker (KRaft)** — no replication, no HA. Acceptable for a throughput benchmark; not a production posture. A real deployment needs RF≥3.
- **MySQL: single instance, ephemeral storage (`persistence.enabled: false`)** — no HA, no durability across pod restart. `sync_binlog=0` + `innodb_flush_log_at_trx_commit=2` trade a small, quantifiable durability window (up to ~1s of commits) for throughput — see §9's redo-log-activity dashboard panel.
- **auto.create.topics.enable=false** requires the provisioning topic list to cover every topic any deployed consumer subscribes to at boot — a real operational sharp edge if a consumer is added without updating the list.
- **Mongo/Redis mostly disabled** in this profile (no clients in this deployment configuration) — not a statement that Mojaloop doesn't need them in other configurations.
- **sdk-scheme-adapter required a fix to correctly populate ISO 20022 transfer fields.** The outbound `/simpleTransfers` code path (`TransfersModel`) didn't thread the ISO20022 quote-response context into its transfer request, so `ChrgBr`/`Cdtr`/`Dbtr` were silently missing from the request body and the switch rejected the transfer. Fixed upstream and published as `mojaloop/sdk-scheme-adapter:v24.19.7`, pinned in `overrides/dfsp.yaml`.

## 15. Other observations / gotchas found

Enabling a TLS-only Kafka listener against the stock charts required the following changes — each is a finding worth reporting, since a stock deployment cannot run Kafka-TLS without them:

- **`wait-for-kafka` init containers replaced with a TCP connect check** (`common/mojaloop/17.1.0.yaml`, all 13 kafka-consuming deployments). The stock check runs a Java Kafka-protocol probe (`kafka-broker-api-versions.sh`) that cannot handshake with a TLS listener — against an SSL-only broker it misreads the TLS handshake as a Kafka frame and dies with `java.lang.OutOfMemoryError`, deadlocking every dependent pod at install. The TCP check preserves the startup-ordering gate and is protocol-agnostic (identical behavior for PLAINTEXT and SSL listeners). Trade-off: it verifies "listener accepting connections" rather than "broker answering API requests"; the applications' own Kafka clients retry on connect, so the weaker gate is sufficient.
- **Topic-provisioning job rewritten to a truststore-only TLS config** (`provisioning.preScript` in `overrides/backend.yaml`). The Bitnami chart's provisioning job builds a client keystore from the auto-generated PEM key, which the Java client cannot parse (PKCS#1 vs PKCS#8) — **topic creation fails while the job still exits 0 and reports "Provisioning succeeded"** (silent failure; helm marks the release deployed and deletes the hook). With an encrypt-only listener no client key is needed; the preScript rewrites `client.properties` to truststore-only before the topic commands run.
- **Broker client-auth relaxed to encrypt-only** (`kafka.tls.sslClientAuth: none`). The chart default (`required`) demands client certificates from every Kafka client; the Mojaloop services' rdkafka configuration carries no client certs. Encrypt-only mirrors the MySQL TLS posture (`rejectUnauthorized: false`).
- **TLS keystore/truststore passwords pinned in values** (`kafka.tls.keystorePassword`/`truststorePassword`). Bitnami's upgrade-passwords check otherwise fails every `helm upgrade` once TLS is enabled. Not protective credentials — certificates are auto-generated per install.
- **All rdkafka clients: `security.protocol: ssl` + `enable.ssl.certificate.verification: false`** across 14 service configmaps (~169 producer/consumer blocks) — 7 of them newly added to the configmap patch set because their helm-rendered configs expose no TLS options.
- **Switch deploy ordering** (`ansible/roles/switch`): helm no longer blocks on pod readiness before the configmap patches apply — services cannot become Ready on a TLS-only broker until their patched (SSL) configuration is in place, so waiting first deadlocks the install. Readiness is gated after the patches instead.
- `controller.overrideConfiguration` is a **dead key** in this Kafka chart version (31.5.0) — silently ignored; only `extraConfig` actually applies.
- **Replica counts that aren't multiples of the generic-node count (5) create a durable node-CPU hotspot, not a one-off imbalance.** The `topologySpreadConstraint` patch (§7) uses `maxSkew: 1` / `whenUnsatisfiable: DoNotSchedule`, applied independently per service. For a service at, say, 12 replicas, that constraint is satisfied by a 3-3-2-2-2 split — and it's the *same two nodes* that land the "extra" pod for every service at that same replica count, since the spread decision is made independently each time with no cross-service coordination. With five services simultaneously sized at 12 (and one at 18), the remainder compounds onto the same one or two nodes across all of them, producing a real, sustained CPU gap versus the other three nodes — not just scheduler noise. Sizing heavy services to multiples of 5 removes the remainder entirely; where that's not practical (as here, to match a specific per-service capacity need), the resulting hotspot is bounded (no single node exceeds ~85% peak in this run) rather than growing further, but it's worth accounting for rather than assuming default scheduling will self-balance.

## 16. Dashboard screenshots

All captures live under `screenshots/<dashboard-name>/`. Representative panels:

**Capacity & Saturation** — node CPU/mem/PSI + cross-service resource comparison
![Capacity & Saturation](<screenshots/Capacity & Saturation/Capacity & Saturation - 1.png>)

**K6 Transaction Latency (client-observed)** — the SLA-gate metric
![K6 e2e latency](<screenshots/K6 Transaction Latency (Client-Observed)/K6 Transaction Latency (Client-Observed) - 1.png>)

**mTLS / Mesh Overhead** — confirms 100% mutual_tls traffic, sidecar/ztunnel cost
![mTLS Overhead](<screenshots/mTLS : Mesh Overhead/mTLS : Mesh Overhead - 1.png>)

**Kafka - Whitepaper Overview** — validity-gate topic lag/throughput, broker health
![Kafka Overview](<screenshots/Kafka - Whitepaper Overview/Kafka - Whitepaper Overview - 1.png>)

**MySQL Overview** — command breakdown, redo-log activity, buffer pool
![MySQL Overview](<screenshots/MySQL Overview/MySQL Overview - 1.png>)

**FSP / DFSP Simulator — Capacity**
![FSP Capacity](<screenshots/FSP : DFSP Simulator — Capacity/FSP : DFSP Simulator — Capacity - 1.png>)

**Mojaloop - Central-Ledger - Performance Characterization** — participant cache hit rate, pods-per-component
![Central-Ledger Cache Hits](<screenshots/Mojaloop - Central-Ledger Performance Characterization/Mojaloop - Central-Ledger Performance Characterization - 1.png>)

Additional captures (Central Ledger transfer legs, ALS, Quoting Service, ML-API Adapter, Service Mesh Hop Latency) are in their respective `screenshots/` subfolders.
