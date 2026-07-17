# Baseline snapshot — v17.1.0 mtls-wireguard 500tps (info) — PRE pod-pod TLS

**Purpose:** frozen "before" reference to diff against after enabling **STRICT `PeerAuthentication`**
(pod-to-pod mTLS on the switch). Captured 2026-07-04.

Current mesh state = Istio sidecars present but intra-switch mTLS is **PERMISSIVE**
(encrypted opportunistically, plaintext allowed). This baseline is that state.

---

## Run identity (RUN-E — clean full-flow run)
- Window: **2026-07-04T01:05:35Z → 01:39:36Z** (~34 min); epochs S=1783127135 E=1783129176
- version **v17.1.0**, **mtls-wireguard**, **500 TPS**, **1,000,000 transfers**
- **log_level = info** (all switch services)
- **NODE_OPTIONS=`--max-semi-space-size=64`** on switch (9 svcs) + DFSP (scheme-adapter **and** backend)
- Images: ml-api-adapter **v16.10.1**, account-lookup-service **v17.16.1**, quoting **v17.12.1**,
  central-ledger v19.8.x, sdk-scheme-adapter **v24.19.6**, mojaloop-simulator v15.4.2
- DFSP scheme-adapter replicas: fsp201/202 = **16**, fsp203–208 = **4**
- backend: mysql SERVER tls.enabled=true BUT app clients `*_db_ssl_enabled=false` + no `require_secure_transport` → **app↔MySQL is PLAINTEXT in practice** (server offers TLS, apps don't dial it). kafka/mysql ephemeral (throughput-max tuning).
- **Encryption state today: DFSP↔switch edge = mTLS (Istio). INTERNAL switch traffic (app↔app HTTP, app↔Kafka, app↔MySQL/Mongo/Redis) = PLAINTEXT.** Sidecars only on DFSP-facing pods (ALS, quoting-handler, ml-api svc/notif); central-ledger/position/prepare/fulfil handlers + all datastores have NO sidecar. No PeerAuthentication (PERMISSIVE default).

## Validity gate (confirms full-flow — cross-check after any change)
`sum(rate(kafka_topic_partition_current_offset{topic=...}[5m]))`, mid-run:
| topic | msgs/s | per txn |
|---|---|---|
| transfer-prepare | 500 | 1.0 |
| transfer-fulfil | 500 | 1.0 |
| notification-event | 1000 | 2.0 |
| transfer-position-batch | 1000 | 2.0 |

Healthy invariant: **prepare == fulfil**, **notif == position == 2×prepare**. ✅

## k6 results (latency in ms; σ via histogram_stddev on k6 native histograms)
| metric | mean | median | p90 | p95 | p99 | max | **σ** |
|---|---|---|---|---|---|---|---|
| **e2e_time** | 590.8 | 577 | 729 | 779 | **928** | 5240 | **166.2** |
| transfer_time | 443.1 | 429 | 563 | 609 | 739 | 4590 | 141.7 |
| quote_time | 126.0 | 124 | 195 | 215 | 249 | 1170 | 52.4 |
| discovery_time | 21.5 | 18 | 31 | 39 | 65 | 1500 | 14.9 |
| http_req_duration | 200.6 | 124 | 481 | 535 | 645 | — | — |

- **actual TPS 499.7**, success **99.96%**, completed 999,412, dropped_iterations 190, failed 398
- e2e CoV (σ/mean) = 28%

## Prometheus infra (avg over run window)
| metric | value |
|---|---|
| **node CPU peak** | **89.2%** (116=89, 245=80, 138=76, 132=74, 72=68, 78=62; infra nodes lower) |
| softirq per node | **0.47–0.54 cores** (low; no creep despite sidecars) |
| **switch app CPU** | **20.8 cores** |
| **istio-proxy sidecar CPU** | **2.05 cores** |
| istio-ingressgateway CPU | 2.69 cores |
| eventloop-lag max (by svc) | 107–157 ms (ml-svc 157, quoting 147, position 143, fulfil 130, prepare 107) |
| kafka consumer lag (peak) | notif 171, prepare 67, fulfil 105, posbatch 160 (all flat — keeping up) |
| istio-proxy sidecars | 38 |
| CPU steal | ~0% (no noisy-neighbor) |

## Reference: error baseline (RUN-A, for context)
Same stack at **log_level=error**: node CPU peak **~71%**, softirq 0.3–0.47c, switch app **17.2 cores**,
GC major p99 61–98ms, e2e **p99 793ms** (robust <1s, ~30% headroom). Notif volume identical (1000/s).

---

## What enabling pod-pod TLS (STRICT) is expected to move — WATCH THESE
Primary comparison metrics (this baseline → after):
- **istio-proxy sidecar CPU** (2.05 c) — expect ↑ (more intra-mesh TLS handshakes/encryption)
- **node CPU peak** (89.2%) — expect ↑ ; already near saturation at info, so headroom risk
- **softirq** (0.47–0.54 c) — may ↑ (more encrypted PPS)
- **e2e p99** (928 ms) and **σ** (166 ms) — expect ↑ / more variable (extra TLS per hop, less headroom)
- switch app CPU (20.8 c) — expect roughly flat (TLS work is in the sidecar, not the app)

### Caveat for the comparison
At **89% switch CPU** the info result is **near saturation** → e2e p99 is run-variance ~0.9–1.2s
(RUN-E good draw 928ms; a sibling RUN-D bad draw 1225ms, identical infra). Pod-pod TLS ADDS CPU →
less headroom → expect p99 to rise and get noisier. To attribute changes cleanly, run 2–3 times
each side and compare distributions (mean/σ), not a single run. Consider recovering headroom first
(trim ALS logging, or +switch app-node) so the TLS delta isn't masked by saturation noise.

### How to reproduce these numbers for the "after" run
```promql
# whole-run stats (@ = run END epoch; k6 native histogram is cumulative)
histogram_avg / histogram_stddev / histogram_quantile(0.99, k6_e2e_time_seconds @ <END>)
# infra (@ = END, [30m:1m] subquery)
max(100*(1-avg by(instance)(avg_over_time(rate(node_cpu_seconds_total{mode="idle"}[3m])[30m:1m] @ <END>))))
avg_over_time(sum(rate(container_cpu_usage_seconds_total{namespace="mojaloop",container="istio-proxy"}[3m]))[30m:1m] @ <END>)
# validity gate
sum(rate(kafka_topic_partition_current_offset{topic="topic-transfer-fulfil"}[5m] @ <MID>))
```
